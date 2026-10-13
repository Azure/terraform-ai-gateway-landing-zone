# LLM backends are derived from the Foundry deployments of stacks/platform. The Unified AI API is on,
# so the contracts cover the three LLM APIs that run the security-handler (Azure OpenAI, Universal LLM,
# Unified AI).
inference_api_type = "OpenAIV1"
features = {
  unified_ai_api        = true
  api_center_onboarding = false
}
model_aliases = [
  { name = "fast", models = ["gpt-5.4-mini"], strategy = "priority" },
]
