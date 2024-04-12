class FreshdeskHandler < AbstractHandler
  require 'rubygems'
  require 'rest_client'
  require 'json'
  require 'pry'
  require 'colorize'
  require_relative 'helper'
  include Helper

  @@fresh_subdomain = 'buk'

# STATUS	VALUE
# Open	2
# Pending	3
# Resolved	4
# Closed	5

  STATUS_VALUE = {
    Open: 2,
    Pending: 3,
    Resolved: 4,
    Closed: 5,
    esperando_cliente: 6,
    esperando_aprobacion: 20,
    esperando_deploy: 28,
    en_curso: 13,
  }

  def initialize(api_key, agent_id: 69016003139)
    @api_key = api_key
    @agent_id = agent_id
  end
  
  def handle
    date = (Date.today - 20).strftime("%Y-%m-%d")
    # %20OR%20status:3
    # query = "\"agent_id:#{@agent_id}%20AND%20status:2%20OR%20status:3%20OR%20status:28%20OR%20status:20%20AND%20created_at:>%27#{date}%27\""
    # query = "\"agent_id:#{@agent_id}%20AND%20created_at:>%27#{date}%27\""
    # %20OR%20status:3%20OR%20status:28%20OR%20status:20
    query = "\"agent_id:#{@agent_id}%20AND%20status:28%20AND%20created_at:>%27#{date}%27\""
    api_path = "/api/v2/search/tickets?query=#{query}"
    fresh_url = "https://#{@@fresh_subdomain}.freshdesk.com/#{api_path}"


    # fresh_url = "https://buk.freshdesk.com/api/v2/tickets?updated_since=#{date}"
    site = RestClient::Resource.new(fresh_url, @api_key, 'X')

    begin
      response = site.get(:accept => 'application/json')

      # cambia cuando se obtiene la data desde un filtro o desde un endpoint directo
      # data = JSON.parse(response.body)
      data = JSON.parse(response.body)['results']

      super({fresh_data: data})
    rescue RestClient::Exception => exception
      puts "X-Request-Id : #{exception.response.headers[:x_request_id]}"
      puts "Response Code: #{exception.response.code} \n Response Body: #{exception.response.body} \n"
    end
  end
end
