class FreshdeskConnection
  require 'rubygems'
  require 'rest_client'
  require 'json'
  require 'pry'
  require 'colorize'
  require_relative 'helper'
  include Helper

  @@fresh_subdomain = 'buk'

  def initialize(api_key, agent_id: 69016003139)
    @api_key = api_key
    @agent_id = agent_id
    # agent_id = 69000377606 #clau
  end

  def show_tickets
    date = (Date.today - 15).strftime("%Y-%m-%d")
    query = "\"agent_id:#{@agent_id}%20AND%20status:5%20AND%20created_at:>%27#{date}%27\""
    api_path = "/api/v2/search/tickets?query=#{query}"
    fresh_url = "https://#{@@fresh_subdomain}.freshdesk.com/#{api_path}"

    site = RestClient::Resource.new(fresh_url, @api_key, 'X')

    data = []
    begin
      response = site.get(:accept => 'application/json')
      # puts "responde_code #{response.code} \n response body #{response.body}"
      if response.code == 200

        JSON.parse(response.body)["results"].each do |attr|
          data.push({
            ticket: attr["id"],
            titulo: attr["subject"],
            cliente: attr["cf_pgina_cliente"],
            descripcion: attr["description_text"],
          })
        end

        data.map do |e|
          e.each do |k, v|
            puts "#{k}:".colorize(:yellow) + " #{v}".colorize(get_color(v))
          end
        end
      end
      data
    rescue RestClient::Exception => exception
      puts "X-Request-Id : #{exception.response.headers[:x_request_id]}"
      puts "Response Code: #{exception.response.code} \n Response Body: #{exception.response.body} \n"
    end
  end

  def get_tickets
    date = (Date.today - 15).strftime("%Y-%m-%d")
    query = "\"agent_id:#{@agent_id}%20AND%20status:5%20AND%20created_at:>%27#{date}%27\""
    api_path = "/api/v2/search/tickets?query=#{query}"
    fresh_url = "https://#{@@fresh_subdomain}.freshdesk.com/#{api_path}"

    site = RestClient::Resource.new(fresh_url, @api_key, 'X')

    begin
      response = site.get(:accept => 'application/json')
      response.body
    rescue RestClient::Exception => exception
      puts "X-Request-Id : #{exception.response.headers[:x_request_id]}"
      puts "Response Code: #{exception.response.code} \n Response Body: #{exception.response.body} \n"
    end
  end
end