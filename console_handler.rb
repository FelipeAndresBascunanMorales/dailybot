class ConsoleHandler < AbstractHandler

  def handle(request)
    key, value = request.to_a.flatten
    case key
    when :ticket_summarized
      value = [value] unless value.is_a?(Array)
      print_ticket_summarized(value)
      choosen_ticket = choose_ticket(value)

      ticket_to_work = {ticket_to_work: choosen_ticket}
      super(ticket_to_work)
    end
  end

  def self.first_interaction
    puts 'hello'
  end

  def print_ticket_summarized(tickets)
    tickets.each do |ticket|

      summary = ticket['summary']
      subdomain = ticket['company']
      ticket_id = ticket['id']

      puts "#{ticket_id}".colorize(:yellow) + ' ' + "#{subdomain}" + ' ' + "#{summary}"
    end
  end

  def choose_ticket(tickets)
    puts "do you want to work in a ticket?"
    puts "enter the ticket id if you want"
    puts "ctrl+c or exit"
    ticket_selected = gets.chomp
    if ['exit', 'n', 'no', nil, '', ' '].include?(ticket_selected.downcase)
      puts 'bye'
      exit
    end

    ticket = tickets.select{|t| t['id'] == ticket_selected.to_i}.first
    if ticket.nil?
      puts "vamos de nuevo"
      choose_ticket(tickets)
    end

    {
      folder_name: "#{ticket['id']} #{ticket['company']}",
      ticket: ticket
    }
  end

  def self.print_link(link, link_text = 'download', message, wait: true)
    puts "#{message} " + "\e]8;;#{link}\a#{link_text}\e]8;;\a"
    gets if wait
  end

  def self.print_folder(path, message, wait: true)
    puts message
    puts "#{path}/"
    gets if wait
  end
end
