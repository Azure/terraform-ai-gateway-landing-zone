inference_api_type = "OpenAIV1"

features = {
  unified_ai_api        = true
  ai_model_inference    = true
  openai_realtime       = true
  api_center_onboarding = true
}

model_aliases = [
  { name = "fast", models = ["gpt-5.4-mini"], strategy = "priority" },
  { name = "balanced", models = ["gpt-5.4", "gpt-5.4-mini"], strategy = "weighted", weights = [70, 30] },
]
