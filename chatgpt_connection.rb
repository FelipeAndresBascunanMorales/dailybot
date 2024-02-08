class ChatgptConnection
  
  require 'rubygems'
  require 'dotenv'
  require 'rest-client'
  require 'json'
  require 'pry'
  require 'colorize'
  require_relative 'helper'
  
  def initialize(api_key)
    @api_key = api_key
  end

  def get_tickets_summary(tickets)

    openai_url = "https://api.openai.com/v1/chat/completions"

    payload = {
      "model": "gpt-4-turbo-preview",
      "messages": [
        {
          "role": "system",
          "content": "you will gonna receive an array with the data from tickets (in spanish). Your work is to return an json object with the following structure:\n[\n  {\n    id: Number,\n    title: String,\n    type: String[centra/bono/banco],\n    new_or_fix: String[nuevo/fix],\n    company: String,\n    summary: String,\n  },\n  ...\n]\n\nattributes definition:\nid: is the same number of the ticket\ntitle: corresponds to the subject field, \n\ntype:\nthe most important attribute is the type, your work is to infers the type based in the data provided, the options are:\n\"centra\": when the ticket correspond to an accounting centralization (\"Centralización contable\" in Spanish) or accounting file.\n\"bono\": when the requirement is related to an settlement item\n\"banco\": when the ticket is related to an personalized format for a file that the bank will accept to generate payments or money transfers\n\ncompany: Is our client you can take the company name in the field custom_url_empresa or from the subdomain in the url subdomain.buk.[cl|pe|co|mx|br] \n\nsummary: The summary attribute must be short, less that 6 words.\n\nnew_or_fix: that field must be \"nuevo\" for tickets that require something new or \"fix\" if in the tickets is required some kind of modification.\n"
        },
        {
          "role": "user",
          "content": tickets
        }
      ],
      "temperature": 1,
      "max_tokens": 4096,
      "top_p": 1,
      "frequency_penalty": 0,
      "presence_penalty": 0
    }

    JSON.parse(tickets)
    response = RestClient.post(openai_url, payload.to_json, {content_type: "application/json", :Authorization => "Bearer #{@api_key}"})
    content = JSON.parse(response.body)&.dig("choices",0, "message", "content")
    content = content.gsub(/^```json\s*|```$/, '')
    JSON.parse(content)
  end
end
