class ReminderBot
  attr_accessor :users_data

  def initialize(bot_api)
    @bot = bot_api # Это может быть реальный bot.api или мок для тестов
    @users_data = {}
  end

  def handle_update(update)
    if update.is_a?(Telegram::Bot::Types::CallbackQuery)
      handle_callback(update)
    elsif update.is_a?(Telegram::Bot::Types::Message) && update.text
      handle_message(update)
    end
  end

  def handle_message(message)
    uid = message.from.id
    @users_data[uid] ||= { tasks: [], status: nil, current_task: {} }
    user = @users_data[uid]

    case message.text
    when "/start"
      user[:status] = nil
      # Здесь твоя логика меню
    when "Создать задачу"
      user[:status] = :wait_for_title
      @bot.send_message(chat_id: message.chat.id, text: "Напишите название задачи:")
    else
      process_state(message, user)
    end
  end

  def process_state(message, user)
    case user[:status]
    when :wait_for_title
      user[:current_task][:title] = message.text
      user[:status] = :wait_for_date
      @bot.send_message(chat_id: message.chat.id, text: "Введите дату:")
    end
  end

  def check_tasks
    now = Time.now
    @users_data.each do |uid, data|
      due = data[:tasks].select { |t| t[:date] <= now }
      due.each do |task|
        @bot.send_message(chat_id: uid, text: "⏰ НАПОМИНАНИЕ: #{task[:title]}")
      end
      data[:tasks].delete_if { |t| t[:date] <= now }
    end
  end
end
