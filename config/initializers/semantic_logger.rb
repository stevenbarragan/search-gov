# frozen_string_literal: true

Rails.application.configure do
  config.semantic_logger.application = ENV.fetch('APP_NAME', 'bot_detection')
end