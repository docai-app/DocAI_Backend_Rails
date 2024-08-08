# lib/openai_client.rb
module OpenAIClient
  def self.client
    @client ||= OpenAI::Client.new
  end

  class << self
    def transcribe_audio(audio_file)
      response = client.audio.transcribe(
        parameters: {
        model: "whisper-1",
        file: audio_file
      })
    end

    def generate_image(prompt, size: '512x512')
      response = client.images.generate(
        parameters: { 
          model: "dall-e-3",
          prompt: prompt, 
          size: "1024x1024",
          quality: "hd",
          n: 1 
        })
    end

    def tts(text, voice)
      if voice == "man"
        voice = "echo"
      else
        voice = "alloy"
      end

      response = client.audio.speech(
        parameters: {
          model: "tts-1",
          input: text,
          voice: voice
        }
      )
      
    end
  end
end
