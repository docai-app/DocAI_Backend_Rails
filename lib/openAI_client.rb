# frozen_string_literal: true

# lib/openai_client.rb
module OpenAIClient
  def self.client
    @client ||= OpenAI::Client.new
  end

  class << self
    def transcribe_audio(audio_file)
      client.audio.transcribe(
        parameters: {
          model: 'whisper-1',
          file: audio_file,
          language: 'en'
        }
      )
    end

    def generate_image(prompt, size: '512x512')
      client.images.generate(
        parameters: {
          model: 'dall-e-3',
          prompt:,
          size: '1024x1024',
          quality: 'hd',
          n: 1
        }
      )
    end

    def tts(text, voice)
      voice = if voice == 'man'
                'echo'
              else
                'alloy'
              end

      client.audio.speech(
        parameters: {
          model: 'tts-1',
          input: text,
          voice:
        }
      )
    end
  end
end
