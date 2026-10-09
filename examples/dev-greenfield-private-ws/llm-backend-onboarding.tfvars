# LLM backends are derived from the Foundry deployments of stacks/platform.
inference_api_type = "OpenAIV1"
features = {
  unified_ai_api        = false
  api_center_onboarding = true
}
model_aliases = [
  { name = "fast", models = ["gpt-5.4-mini"], strategy = "priority" },
]
