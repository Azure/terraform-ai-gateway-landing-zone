import datetime, json, os, subprocess, requests, sys, time, traceback

# Define ANSI escape code constants vor clarity in the print commands below
RESET_FORMATTING = "\x1b[0m"
BOLD_BLUE = "\x1b[1;34m"
BOLD_RED = "\x1b[1;31m"
BOLD_GREEN = "\x1b[1;32m"
BOLD_YELLOW = "\x1b[1;33m"

print_command = lambda command='': print(f"⚙️ {BOLD_BLUE}Running: {command} {RESET_FORMATTING}")
print_error = lambda message, output='', duration='': print(f"❌ {BOLD_YELLOW}{message}{RESET_FORMATTING} ⌚ {datetime.datetime.now().time()} {duration}{' ' if output else ''}{output}")
print_info = lambda message: print(f"👉🏽 {BOLD_BLUE}{message}{RESET_FORMATTING}")
print_message = lambda message, output='', duration='': print(f"👉🏽 {BOLD_GREEN}{message}{RESET_FORMATTING} ⌚ {datetime.datetime.now().time()} {duration}{' ' if output else ''}{output}")
print_ok = lambda message, output='', duration='': print(f"✅ {BOLD_GREEN}{message}{RESET_FORMATTING} ⌚ {datetime.datetime.now().time()} {duration}{' ' if output else ''}{output}")
print_warning = lambda message, output='', duration='': print(f"⚠️ {BOLD_YELLOW}{message}{RESET_FORMATTING} ⌚ {datetime.datetime.now().time()} {duration}{' ' if output else ''}{output}")

def mask_sensitive_values(data, sensitive_keys=None):
    """
    Recursively mask sensitive values in nested dictionaries and lists.
    
    Args:
        data: The data structure to process (dict, list, or primitive)
        sensitive_keys: List of key names to mask (case-insensitive). 
                       Defaults to ['apiKey', 'api_key', 'key', 'secret', 'password']
    
    Returns:
        A copy of the data with sensitive values replaced by '########'
    """
    if sensitive_keys is None:
        sensitive_keys = ['apikey', 'api_key', 'secret', 'password']
    
    sensitive_keys_lower = [k.lower() for k in sensitive_keys]
    
    if isinstance(data, dict):
        return {
            k: '########' if k.lower() in sensitive_keys_lower and isinstance(v, str)
               else mask_sensitive_values(v, sensitive_keys)
            for k, v in data.items()
        }
    elif isinstance(data, list):
        return [mask_sensitive_values(item, sensitive_keys) for item in data]
    else:
        return data

class Output(object):
    def __init__(self, success, text):
        self.success = success
        self.text = text

        try:
            self.json_data = json.loads(text)
        except:
            # stdout may contain non-JSON text (progress indicators, warnings) before/after the JSON.
            # Try to extract the outermost JSON object or array from the text.
            self.json_data = Output._extract_json(text)

    @staticmethod
    def _extract_json(text):
        """Extract the first valid JSON object or array from mixed text."""
        for start_char, end_char in [('{', '}'), ('[', ']')]:
            start = text.find(start_char)
            if start == -1:
                continue
            # Search from the end backwards for the matching closing character
            end = text.rfind(end_char)
            if end > start:
                try:
                    return json.loads(text[start:end + 1])
                except json.JSONDecodeError:
                    continue
        return json.loads("{}")  # return empty dict if no valid JSON found


# =============================================================================
# Terraform stacks bridge
# -----------------------------------------------------------------------------
# The deployment is split into stacks under stacks/<stack>, driven by the
# Taskfile and per-environment folders environments/<env>/ (common.tfvars,
# backend.hcl, <stack>.tfvars, access-contracts/<use-case>.tfvars). The helpers
# below let notebooks generate var files there, run a stack (`task` when it is
# installed, plain `terraform -chdir=stacks/<stack>` otherwise) and read stack
# outputs with `terraform -chdir=stacks/<stack> output -json`.
#
# The validation notebooks were originally written for an `azd`-deployed
# environment and read config via `azd env get-value VAR`. When no azd value is
# available, `azd_env_get` falls back to the stack outputs (or common.tfvars)
# listed in `_TF_OUTPUT_ALIASES`, so existing `load_azd_env(...)` calls keep
# working. Set CITADEL_ENV (default "dev") / CITADEL_REPO_ROOT to point them at
# another environment or checkout.
# =============================================================================

# Repository root (Taskfile.yml, stacks/, environments/). `shared/` sits at the root.
REPO_ROOT = os.path.abspath(os.environ.get("CITADEL_REPO_ROOT", os.path.join(os.path.dirname(__file__), "..")))
DEFAULT_ENV = os.environ.get("CITADEL_ENV", "dev")

# azd env var name -> (stack, terraform output name); stack "common" = environments/<env>/common.tfvars
_TF_OUTPUT_ALIASES = {
    "AZURE_RESOURCE_GROUP":          ("platform", "resource_group_name"),
    "GOVERNANCE_HUB_RESOURCE_GROUP": ("platform", "resource_group_name"),
    "AZURE_LOCATION":                ("common", "location"),
    "LOCATION":                      ("common", "location"),
    "AZURE_SUBSCRIPTION_ID":         ("common", "subscription_id"),
    "KEY_VAULT_NAME":                ("platform", "key_vault_name"),
    "AI_FOUNDRY_ENDPOINTS":          ("platform", "foundry_endpoints"),
    "APIM_NAME":                     ("platform", "apim_name"),
    "APIM_GATEWAY_URL":              ("platform", "apim_gateway_url"),
    "UNIVERSAL_LLM_API_URL":         ("llm-backend-onboarding", "universal_llm_api_url"),
}

# Cache of `terraform output -json` keyed by (repo_root, env, stack, state_key).
_tf_outputs_cache = {}


def _exe(name):
    import shutil
    return shutil.which(name) or name


def env_dir(env=None, repo_root=None):
    """environments/<env> (absolute)."""
    return os.path.join(repo_root or REPO_ROOT, "environments", env or DEFAULT_ENV)


def stack_dir(stack, repo_root=None):
    """stacks/<stack> (absolute)."""
    return os.path.join(repo_root or REPO_ROOT, "stacks", stack)


def hcl_str(value):
    """Render a Python value as a double-quoted HCL string literal."""
    return '"' + str(value).replace("\\", "\\\\").replace('"', '\\"') + '"'


def read_common_tfvars(env=None, repo_root=None):
    """Top-level `name = "value"` string assignments of environments/<env>/common.tfvars."""
    import re
    path = os.path.join(env_dir(env, repo_root), "common.tfvars")
    values = {}
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                m = re.match(r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"([^"]*)"', line)
                if m:
                    values[m.group(1)] = m.group(2)
    except OSError:
        pass
    return values


def write_tfvars(path, content, backup=True):
    """Write a generated var file (creating its folder). An existing file that was not
    generated by a notebook is first copied to <file>.bak (git-ignored)."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if backup and os.path.isfile(path):
        with open(path, encoding="utf-8") as f:
            existing = f.read()
        if "Generated:" not in existing and not os.path.exists(path + ".bak"):
            with open(path + ".bak", "w", encoding="utf-8") as f:
                f.write(existing)
            print_warning(f"Existing {path} backed up to {path}.bak")
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    return path


def _exec(args, cwd=None, quiet=False):
    """Run an argument list without a shell (az.cmd / task.cmd via cmd /c on Windows)."""
    run_args = args
    if os.name == "nt" and str(args[0]).lower().endswith((".cmd", ".bat")):
        run_args = ["cmd", "/c", *args]
    if not quiet:
        print_command(" ".join(str(a) for a in args))
    return subprocess.run(run_args, cwd=cwd, capture_output=True, text=True, encoding="utf-8", errors="replace")


def _stack_init(stack, env, state_key, repo_root, quiet=False):
    backend = os.path.join(env_dir(env, repo_root), "backend.hcl")
    args = [_exe("terraform"), f"-chdir={stack_dir(stack, repo_root)}", "init", "-reconfigure", "-input=false",
            f"-backend-config={backend}"]
    if state_key:
        args.append(f"-backend-config=key={state_key}")
    return _exec(args, quiet=quiet)


def run_stack(stack, env=None, var_file=None, state_key=None, auto_approve=True, destroy=False,
              repo_root=None, use_task=None, print_output=True):
    """Plan and apply (or destroy) one stack for an environment.

    Same as `task apply|destroy STACK=<stack> ENV=<env> [STATE_KEY=..] [VAR_FILE=..]`:
      terraform -chdir=stacks/<stack> init -reconfigure -backend-config=environments/<env>/backend.hcl [-backend-config=key=<state_key>]
      terraform -chdir=stacks/<stack> plan -out=tfplan [-destroy] -var-file=common.tfvars -var-file=<var_file>
      terraform -chdir=stacks/<stack> apply tfplan          (only when auto_approve)

    var_file defaults to environments/<env>/<stack>.tfvars; state_key defaults to the
    backend.hcl key (access contracts use <use-case>.tfstate). use_task=None uses `task`
    when it is on PATH (and auto_approve is set). Returns an Output.
    """
    import shutil
    env = env or DEFAULT_ENV
    root = repo_root or REPO_ROOT
    edir = env_dir(env, root)
    var_file = os.path.abspath(var_file) if var_file else os.path.join(edir, f"{stack}.tfvars")
    common = os.path.join(edir, "common.tfvars")
    for required in (common, os.path.join(edir, "backend.hcl"), var_file):
        if not os.path.isfile(required):
            print_error(f"Missing {required} (see examples/ and `task bootstrap ENV={env}`)")
            return Output(False, "")
    if use_task is None:
        use_task = bool(shutil.which("task")) and auto_approve

    start_time = time.time()
    label = f"{'destroy' if destroy else 'apply'} {stack} ({env}{', ' + state_key if state_key else ''})"
    steps = []
    if use_task:
        args = [_exe("task"), "-d", root, "destroy" if destroy else "apply", f"STACK={stack}", f"ENV={env}", f"VAR_FILE={var_file}"]
        if state_key:
            args.append(f"STATE_KEY={state_key}")
        steps.append(args)
    else:
        sdir = stack_dir(stack, root)
        plan = [_exe("terraform"), f"-chdir={sdir}", "plan", "-input=false", "-out=tfplan",
                f"-var-file={common}", f"-var-file={var_file}"]
        if destroy:
            plan.insert(3, "-destroy")
        steps.append(None)  # init
        steps.append(plan)
        if auto_approve:
            if destroy:
                steps.append([_exe("terraform"), f"-chdir={sdir}", "apply", "-input=false", "tfplan"])
            else:
                steps.append([sys.executable, os.path.join(root, "scripts", "apply-stack.py"),
                              sdir, "--", f"-var-file={common}", f"-var-file={var_file}"])

    text, success = "", True
    for args in steps:
        proc = _stack_init(stack, env, state_key, root) if args is None else _exec(args)
        text += (proc.stdout or "") + ("\n" + proc.stderr if proc.stderr else "")
        if proc.returncode != 0:
            success = False
            break

    for key in [k for k in _tf_outputs_cache if k[1] == env and k[2] == stack]:
        _tf_outputs_cache.pop(key, None)

    if print_output:
        print(text)
    minutes, seconds = divmod(time.time() - start_time, 60)
    (print_ok if success else print_error)(f"{label} {'succeeded' if success else 'failed'}", "", f"[{int(minutes)}m:{int(seconds)}s]")
    return Output(success, text)


def stack_outputs(stack, env=None, state_key=None, repo_root=None, refresh=False):
    """`terraform -chdir=stacks/<stack> output -json` as {name: value} (cached).

    Initialises the stack against environments/<env>/backend.hcl first (with
    key=<state_key> for access contracts). Returns {} when Terraform is missing,
    the state is empty or the command fails.
    """
    env = env or DEFAULT_ENV
    root = repo_root or REPO_ROOT
    cache_key = (root, env, stack, state_key)
    if not refresh and cache_key in _tf_outputs_cache:
        return _tf_outputs_cache[cache_key]
    outputs = {}
    try:
        if os.path.isfile(os.path.join(env_dir(env, root), "backend.hcl")):
            _stack_init(stack, env, state_key, root, quiet=True)
        proc = _exec([_exe("terraform"), f"-chdir={stack_dir(stack, root)}", "output", "-json"], quiet=True)
        if proc.returncode == 0 and proc.stdout.strip():
            outputs = {k: (v.get("value") if isinstance(v, dict) else v) for k, v in json.loads(proc.stdout).items()}
    except Exception:
        outputs = {}
    _tf_outputs_cache[cache_key] = outputs
    return outputs


def terraform_output_get(name, default=None, stack="platform", env=None, state_key=None, repo_root=None):
    """Return a single stack output value by name.

    Complex (object/array) outputs are JSON-stringified so callers that expect a
    string they can `json.loads(...)` — exactly like an azd env value — keep
    working. Scalar outputs are returned as their native string/number.
    """
    if stack == "common":
        value = read_common_tfvars(env, repo_root).get(name)
    else:
        value = stack_outputs(stack, env, state_key, repo_root).get(name)
    if value is None:
        return default
    if isinstance(value, (dict, list)):
        return json.dumps(value)
    return value


def get_contract_subscription_key(contract_outputs, code="LLM", key_vault_name=None):
    """Primary key of an access-contract subscription (keys are never in Terraform state).

    Reads the Key Vault secret named in `key_vault_secret_names[code].key` when
    key_vault_name is given (key_vault.enabled = true); otherwise, or when that
    fails, calls listSecrets on the subscription resource ID from `subscriptions[code]`.
    """
    secret = ((contract_outputs.get("key_vault_secret_names") or {}).get(code) or {}).get("key")
    if key_vault_name and secret:
        proc = _exec([_exe("az"), "keyvault", "secret", "show", "--vault-name", key_vault_name,
                      "--name", secret, "--query", "value", "-o", "tsv"], quiet=True)
        if proc.returncode == 0 and proc.stdout.strip():
            return proc.stdout.strip()
        print_warning(f"Could not read secret '{secret}' from Key Vault '{key_vault_name}'; falling back to APIM listSecrets.")
    sub_id = (contract_outputs.get("subscriptions") or {}).get(code)
    if not sub_id:
        return None
    proc = _exec([_exe("az"), "rest", "--method", "post", "--url",
                  f"https://management.azure.com{sub_id}/listSecrets?api-version=2024-05-01"], quiet=True)
    if proc.returncode == 0 and proc.stdout.strip():
        try:
            return json.loads(proc.stdout).get("primaryKey")
        except json.JSONDecodeError:
            pass
    print_error(f"Could not list the secrets of {sub_id}", proc.stderr or "")
    return None


def azd_env_get(var_name, default=None):
    """Return the value of an `azd` environment variable for the active azd environment.

    Falls back to the matching stack output (see `_TF_OUTPUT_ALIASES`) when
    the `azd` CLI is unavailable or has no value, so this Terraform port works
    without azd. Returns `default` when neither source has a value. The value is
    returned as a stripped string; callers that expect JSON should `json.loads(...)`
    it themselves.

    Designed for use in validation notebooks so a single `azd_env_get('AZURE_RESOURCE_GROUP')`
    call works on Windows / macOS / Linux without leaking subprocess plumbing into the notebook.
    """
    try:
        result = subprocess.run(
            ["azd", "env", "get-value", var_name],
            capture_output=True, text=True, check=False,
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()
    except FileNotFoundError:
        # On Windows `azd` may resolve only as `azd.cmd` via the shell. Retry
        # through the shell before giving up and falling back to Terraform.
        try:
            result = subprocess.run(
                f"azd env get-value {var_name}",
                capture_output=True, text=True, check=False, shell=True,
            )
            if result.returncode == 0 and result.stdout.strip():
                return result.stdout.strip()
        except Exception:
            pass
    except Exception:
        pass

    # Fall back to the stack outputs (this port deploys with Terraform, not azd).
    alias = _TF_OUTPUT_ALIASES.get(var_name)
    if alias:
        tf_value = terraform_output_get(alias[1], stack=alias[0])
        if tf_value is not None:
            return tf_value

    return default


def azd_env_get_json(var_name, default=None):
    """Like `azd_env_get`, but parses the value as JSON. Returns `default` on any failure."""
    raw = azd_env_get(var_name)
    if not raw:
        return default
    try:
        return json.loads(raw)
    except (json.JSONDecodeError, TypeError):
        return default


def load_azd_env(var_map, verbose=True):
    """Load multiple azd environment variables in one shot.

    `var_map` maps a friendly label to either:
      - a single env-var name (str)            → returns the raw string value
      - a list of fallback env-var names       → returns the first match found
      - a tuple `(names, "json")`              → JSON-decodes the matched value

    Returns a dict keyed by the same labels. Missing values are omitted from the result
    so callers can use `result.get(label, fallback_default)` patterns.

    Example:
        loaded = utils.load_azd_env({
            "resource_group": ["AZURE_RESOURCE_GROUP", "GOVERNANCE_HUB_RESOURCE_GROUP"],
            "location":       ["AZURE_LOCATION", "LOCATION"],
            "llm_backends":   (["LLM_BACKEND_CONFIG", "LLM_BACKENDS_CONFIG"], "json"),
        })
    """
    loaded = {}
    for label, spec in var_map.items():
        names, mode = (spec, "str")
        if isinstance(spec, tuple):
            names, mode = spec
        if isinstance(names, str):
            names = [names]
        value = None
        for n in names:
            v = azd_env_get(n)
            if v:
                value = v
                break
        if value is None:
            if verbose:
                print_warning(f"azd env var not set for '{label}' (looked up: {names})")
            continue
        if mode == "json":
            try:
                value = json.loads(value)
            except json.JSONDecodeError as e:
                if verbose:
                    print_warning(f"azd env var '{label}' is not valid JSON: {e}")
                continue
        loaded[label] = value
    return loaded


def get_current_subscription():
    try:
        output = run("az account show", "Retrieved az account", "Failed to get the current az account")

        if output.success and output.json_data:
            subscription_id = output.json_data['id']
            subscription_name = output.json_data['name']
            print_info(f"Using Subscription ID: {subscription_id} ({subscription_name})")
            return subscription_id
        else:
            print_error("No current subscription found.")
            return None
    except Exception as e:
        print_error(f"Error retrieving current subscription: {e}")
        return None

# Retrieves resources in a resource group
def get_resources(resource_group_name, config):
    if not resource_group_name:
        print_error("Missing resource group name parameter.")
        return

    resources = {}
    try:
        ## retrieve resource group location
        output = run(f"az group show --name {resource_group_name}")

        if output.success:
            print_info(f"Using existing resource group '{resource_group_name}'")
            output = run(f"az group show --name {resource_group_name} -o json", "Retrieved resource group ", "Failed to retrieve resource group")
            if output.success and output.json_data:
                resources['resourceGroupLocation'] = output.json_data["location"]

                ## retrieve resources
                output = run(f'az resource list -g {resource_group_name} -o json', "Listed resources", "Failed to list resources")
                if output.success and output.json_data:
                    for resource in output.json_data:
                        match resource["type"].lower():
                            case "microsoft.operationalinsights/workspaces":
                                resources['logAnalyticsResourceId'] = resource["id"]
                                resources['logAnalyticsResourceName'] = resource["name"]
                            case "microsoft.insights/components":
                                resources['appInsightsResourceId'] = resource["id"]
                                resources['appInsightsResourceName'] = resource["name"]
                                output = run(f'az resource show -g {resource_group_name} -n {resource["name"]} --resource-type "microsoft.insights/components" -o json', "Retrieved App Insights resource", "Failed to retrieve App Insights resource")
                                if output.success and output.json_data:
                                    resources['appInsightsInstrumentationKey'] = output.json_data["properties"]["InstrumentationKey"]
                            case "microsoft.cognitiveservices/accounts":
                                resources['foundryResourceId'] = resource["id"]
                                resources['foundryResourceName'] = resource["name"]
                            case "microsoft.cognitiveservices/accounts/projects":
                                resources['foundryProjectId'] = resource["id"]
                                resources['foundryProjectName'] = resource["name"]
                            case "microsoft.apimanagement/service":
                                resources['apimResourceId'] = resource["id"]
                                resources['apimResourceName'] = resource["name"]
                                resources['apimPrincipalId'] = resource["identity"]["principalId"]
        else:
            return config

    except Exception as e:
        print_error(f"Error retrieving resources: {e}")

    return resources

# Cleans up resources associated with a deployment in a resource group
def cleanup_resources(deployment_name, resource_group_name = None):
    if not deployment_name:
        print_error("Missing deployment name parameter.")
        return

    if not resource_group_name:
        resource_group_name = f"lab-{deployment_name}"

    try:
        print_info(f"🧹 Cleaning up resource group '{resource_group_name}'...")

        # Show the deployment details
        output = run(f"az deployment group show --name {deployment_name} -g {resource_group_name} -o json", "Deployment retrieved", "Failed to retrieve the deployment")

        if output.success and output.json_data:
            provisioning_state = output.json_data.get("properties").get("provisioningState")
            print_info(f"Deployment provisioning state: {provisioning_state}")

            # Delete AI Foundry projects
            output = run(f'az resource list -g {resource_group_name} --resource-type "microsoft.cognitiveservices/accounts/projects"', "Retrieved AI Foundry projects", "Failed to list AI Foundry projects")
            if output.success and output.json_data:
                for resource in output.json_data:
                    print_info(f"Deleting AI Foundry project '{resource['name']}' in resource group '{resource_group_name}'...")
                    output = run(f'az resource delete --ids "{resource['id']}"', f"AI Foundry project '{resource['name']}' deleted", f"Failed to delete AI Foundry project '{resource['name']}'")

            # Delete and purge CognitiveService accounts
            output = run(f"az cognitiveservices account list -g {resource_group_name}", f"Listed CognitiveService accounts", f"Failed to list CognitiveService accounts")
            if output.success and output.json_data:
                for resource in output.json_data:
                    print_info(f"Deleting and purging Cognitive Service Account '{resource['name']}' in resource group '{resource_group_name}'...")
                    output = run(f"az cognitiveservices account delete -g {resource_group_name} -n {resource['name']}", f"Cognitive Services '{resource['name']}' deleted", f"Failed to delete Cognitive Services '{resource['name']}'")
                    output = run(f"az cognitiveservices account purge -g {resource_group_name} -n {resource['name']} -l \"{resource['location']}\"", f"Cognitive Services '{resource['name']}' purged", f"Failed to purge Cognitive Services '{resource['name']}'")

            # Delete and purge APIM resources
            output = run(f" az apim list -g {resource_group_name}", f"Listed APIM resources", f"Failed to list APIM resources")
            if output.success and output.json_data:
                for resource in output.json_data:
                    print_info(f"Deleting and purging API Management '{resource['name']}' in resource group '{resource_group_name}'...")
                    output = run(f"az apim delete -n {resource['name']} -g {resource_group_name} -y", f"API Management '{resource['name']}' deleted", f"Failed to delete API Management '{resource['name']}'")
                    output = run(f"az apim deletedservice purge --service-name {resource['name']} --location \"{resource['location']}\"", f"API Management '{resource['name']}' purged", f"Failed to purge API Management '{resource['name']}'")

            # Delete and purge Key Vault resources
            output = run(f"az keyvault list -g {resource_group_name}", f"Listed Key Vault resources", f"Failed to list Key Vault resources")
            if output.success and output.json_data:
                for resource in output.json_data:
                    print_info(f"Deleting and purging Key Vault '{resource['name']}' in resource group '{resource_group_name}'...")
                    output = run(f"az keyvault delete -n {resource['name']} -g {resource_group_name}", f"Key Vault '{resource['name']}' deleted", f"Failed to delete Key Vault '{resource['name']}'")
                    output = run(f"az keyvault purge -n {resource['name']} --location \"{resource['location']}\"", f"Key Vault '{resource['name']}' purged", f"Failed to purge Key Vault '{resource['name']}'")

            # Delete the resource group last
            print_message(f"🧹 Deleting resource group '{resource_group_name}'...")
            output = run(f"az group delete --name {resource_group_name} -y", f"Resource group '{resource_group_name}' deleted", f"Failed to delete resource group '{resource_group_name}'")

            print_message("🧹 Cleanup completed.")

    except Exception as e:
        print(f"An error occurred during cleanup: {e}")
        traceback.print_exc()

def create_resource_group(resource_group_name, resource_group_location = None):
    if not resource_group_name:
        print_error('Please specify the resource group name.')
    else:
        output = run(f"az group show --name {resource_group_name}")

        if output.success:
            print_info(f"Using existing resource group '{resource_group_name}'")
        else:
            if not resource_group_location:
                print_error('Please specify the resource group location.')
            else:
                print_info(f"Resource group {resource_group_name} does not yet exist. Creating the resource group now...")

                output = run(f"az group create --name {resource_group_name} --location {resource_group_location} --tags source=ai-gateway",
                    f"Resource group '{resource_group_name}' created",
                    f"Failed to create the resource group '{resource_group_name}'")

# Deletes a specific resource based on its type
def delete_resource(resource, resource_group_name):
    resource_name = resource.get("name")
    resource_type = resource.get("type")
    resource_location = resource.get("location")

    print(f"🗑 Deleting {resource_type} '{resource_name}' in resource group '{resource_group_name}'...")

    # API Management
    if resource_type == "Microsoft.ApiManagement/service":
        output = run(f"az apim delete -n {resource_name} -g {resource_group_name} -y", f"API Management '{resource_name}' deleted", f"Failed to delete API Management '{resource_name}'")

        output = run(f"az apim deletedservice purge --service-name {resource_name} --location \"{resource_location}\"", f"API Management '{resource_name}' purged", f"Failed to purge API Management '{resource_name}'")

    # Cognitive Services
    elif resource_type == "Microsoft.CognitiveServices/accounts":
        output = run(f"az cognitiveservices account delete -g {resource_group_name} -n {resource_name}", f"Cognitive Services '{resource_name}' deleted", f"Failed to delete Cognitive Services '{resource_name}'")

        output = run(f"az cognitiveservices account purge -g {resource_group_name} -n {resource_name} -l \"{resource_location}\"", f"Cognitive Services '{resource_name}' purged", f"Failed to purge Cognitive Services '{resource_name}'")

    # Key Vault
    elif resource_type == "Microsoft.KeyVault/vaults":
        output = run(f"az keyvault delete -n {resource_name} -g {resource_group_name}", f"Key Vault '{resource_name}' deleted", f"Failed to delete Key Vault '{resource_name}'")

def get_deployment_output(output, output_property, output_label = '', secure = False) -> str:
    try:
        deployment_output = output.json_data['properties']['outputs'][output_property]['value']

        if output_label:
            if secure:
                print_info(f"{output_label}: ****{deployment_output[-4:]}")
            else:
                print_info(f"{output_label}: {deployment_output}")

        return str(deployment_output)
    except Exception as e:
        error = f"Failed to retrieve output property: '{output_property}'\nError: {e}"
        print_error(error)
        raise Exception(error)

def print_response(response):
    print("Response headers: ", response.headers)

    if (response.status_code == 200):
        print_ok(f"Status Code: {response.status_code}")
        data = json.loads(response.text)
        print(json.dumps(data, indent=4))
    else:
        print_warning(f"Status Code: {response.status_code}")
        print(response.text)

def print_response_code(response):
    # Check the response status code and apply formatting
    if 200 <= response.status_code < 300:
        status_code_str = f"{BOLD_GREEN}{response.status_code} - {response.reason}{RESET_FORMATTING}"
    elif response.status_code >= 400:
        status_code_str = f"{BOLD_RED}{response.status_code} - {response.reason}{RESET_FORMATTING}"
    else:
        status_code_str = str(response.status_code)

    # Print the response status with the appropriate formatting
    print(f"Response status: {status_code_str}")

# Simple: print full error body (JSON if available, else raw text)
def print_full_http_error(response):
    try:
        data = response.json()
        print_error("Request failed. Full JSON body:", json.dumps(data, indent=2))
        # If ARM-style error present, surface message too
        if isinstance(data, dict) and isinstance(data.get("error"), dict):
            code = data["error"].get("code", "")
            msg = data["error"].get("message", "")
            if msg or code:
                print_error(f"Service error:", f"{code} - {msg}")
    except ValueError:
        print_error("Request failed. Full text body:", response.text or "")

def run(command, ok_message = '', error_message = '', print_output = False, print_command_to_run = True):
    if print_command_to_run:
        print_command(command)

    start_time = time.time()

    try:
        completed_process = subprocess.run(
            command,
            shell=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
        output_text = completed_process.stdout or ""
        stderr_text = completed_process.stderr or ""
        success = completed_process.returncode == 0
    except subprocess.CalledProcessError as e:
        output_text = e.output.decode("utf-8", errors="replace") if isinstance(e.output, (bytes, bytearray)) else (e.output or "")
        stderr_text = e.stderr.decode("utf-8", errors="replace") if isinstance(e.stderr, (bytes, bytearray)) else (e.stderr or "")
        success = False

    # Combine stdout and stderr for error reporting, but keep stdout clean for JSON parsing
    combined_text = output_text + ("\n" + stderr_text if stderr_text else "")

    minutes, seconds = divmod(time.time() - start_time, 60)

    print_message = print_ok if success else print_error

    if (ok_message or error_message):
        print_message(ok_message if success else error_message, combined_text if not success or print_output  else "", f"[{int(minutes)}m:{int(seconds)}s]")

    return Output(success, output_text)

def create_bicep_params(policy_xml_filepath, parameters_filepath, bicep_parameters, replacements_list):
    # Read the specified policy XML file
    with open(policy_xml_filepath, 'r') as policy_xml_file:
        policy_template_xml = policy_xml_file.read()

    # Replace the placeholders in the policy XML with the actual values from the replacements_lists array
    for key, value in replacements_list:
        policy_template_xml = policy_template_xml.replace(key, str(value))

    # Set or update the policyXml parameter in the bicep parameters file
    bicep_parameters['parameters'].setdefault('policyXml', {})
    bicep_parameters['parameters']['policyXml']['value'] = policy_template_xml

    # Write the updated bicep parameters to the specified parameters file
    with open(parameters_filepath, 'w') as bicep_parameters_file:
        bicep_parameters_file.write(json.dumps(bicep_parameters))

    print(f"📝 Updated the policy XML in the bicep parameters file '{parameters_filepath}'")

    return bicep_parameters

def update_api_policy(subscription_id, resource_group_name, apim_service_name, api_id, policy_xml):
    # We first need to obtain an access token for the REST API
    output = run(f"az account get-access-token --resource https://management.azure.com/",
        f"Successfully obtained access token", f"Failed to obtain access token")

    if output.success and output.json_data:
        access_token = output.json_data['accessToken']

        print("Updating the API policy...")
        # https://learn.microsoft.com/en-us/rest/api/apimanagement/api-policy/create-or-update?view=rest-apimanagement-2024-06-01-preview
        url = f"https://management.azure.com/subscriptions/{subscription_id}/resourceGroups/{resource_group_name}/providers/Microsoft.ApiManagement/service/{apim_service_name}/apis/{api_id}/policies/policy?api-version=2024-06-01-preview"
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {access_token}"
        }

        body = {
            "properties": {
                "format": "rawxml",
                "value": policy_xml
            }
        }

        response = requests.put(url, headers = headers, json = body)
        if 200 <= response.status_code < 300:
            print_response_code(response)
        else:
            print_response_code(response)
            print_full_http_error(response)

def update_api_operation_policy(subscription_id, resource_group_name, apim_service_name, api_id, operation_id, policy_xml):
    # We first need to obtain an access token for the REST API
    output = run(f"az account get-access-token --resource https://management.azure.com/",
        f"Successfully obtained access token", f"Failed to obtain access token")

    if output.success and output.json_data:
        access_token = output.json_data['accessToken']

        print("Updating the API policy...")
        # https://learn.microsoft.com/en-us/rest/api/apimanagement/api-policy/create-or-update?view=rest-apimanagement-2024-06-01-preview
        url = f"https://management.azure.com/subscriptions/{subscription_id}/resourceGroups/{resource_group_name}/providers/Microsoft.ApiManagement/service/{apim_service_name}/apis/{api_id}/operations/{operation_id}/policies/policy?api-version=2024-06-01-preview"
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {access_token}"
        }

        body = {
            "properties": {
                "format": "rawxml",
                "value": policy_xml
            }
        }

        response = requests.put(url, headers = headers, json = body)
        print_response_code(response)

def get_debug_credentials(apim_service_id, api_id, expire_after = 'PT1H') -> str | None:
    request = {
        "credentialsExpireAfter": expire_after,
        "apiId": f"{apim_service_id}/apis/{api_id}",
        "purposes": ["tracing"]
    }
    output = run(f"az rest --method post --uri {apim_service_id}/gateways/managed/listDebugCredentials?api-version=2023-05-01-preview --body \"{str(request)}\"",
            "Retrieved APIM debug credentials", "Failed to get the APIM debug credentials")
    return output.json_data['token'] if output.success and output.json_data else None
        
def get_trace(apim_service_id, trace_id) -> str | None:
    request = {
        "traceId": trace_id
    }
    output = run(f"az rest --method post --uri {apim_service_id}/gateways/managed/listTrace?api-version=2023-05-01-preview --body \"{str(request)}\"",
            "Retrieved trace details", "Failed to get the trace details")
    return output.json_data if output.success and output.json_data else None
