require "telegram/bot"
require "date"
require "json"
require "time"
require 'dotenv/load'

STORE_FILE = "res/tasks.json"

# --- ЛОГИКА ДАННЫХ ---
def load_data
  return {} unless File.exist?(STORE_FILE)

  begin
    raw = JSON.parse(File.read(STORE_FILE))
    data = {}
    raw.each do |uid_str, user_info|
      uid = uid_str.to_i
      data[uid] = {
        # Добавляем t['id'], если его нет (для старых записей)
        tasks: user_info["tasks"].map do |t|
          {
            id: t["id"] || Time.now.to_f.to_s,
            title: t["title"],
            date: Time.parse(t["date"])
          }
        end,
        status: nil,
        current_task: {}
      }
    end
    data
  rescue StandardError => e
    puts "Ошибка загрузки: #{e.message}"
    {}
  end
end

def save_data
  File.write(STORE_FILE, JSON.pretty_generate($users_data))
end

def delete_task_by_id(uid, task_id)
  return false if $users_data[uid].nil?

  # Удаляем задачу, у которой id совпадает с пришедшим из кнопки
  $users_data[uid][:tasks].delete_if { |t| t[:id].to_s == task_id.to_s }
  save_data
  true
end

# --- ПЛАНИРОВЩИК ---
def start_scheduler(bot)
  Thread.new do
    loop do
      begin
        now = Time.now
        any_notified = false
        $users_data.each do |uid, data|
          next if data[:tasks].empty?

          due = data[:tasks].select { |t| t[:date] <= now }
          due.each do |task|
            bot.api.send_message(chat_id: uid, text: "⏰
            #{task[:title]}
            Пришло время напомнить вам об этой задаче!")
            puts "[#{Time.now.strftime("%H:%M")}] Уведомление отправлено для #{uid}: #{task[:title]}"
            any_notified = true
          end
          data[:tasks].delete_if { |t| t[:date] <= now }
        end
        save_data if any_notified
      rescue StandardError => e
        puts "Ошибка планировщика: #{e.message}"
      end
      sleep 20
    end
  end
end

# --- МЕНЮ ---
def send_main_menu(bot, chat_id, text, image_path = nil)
  full_path = File.expand_path(image_path, Dir.pwd) if image_path
  if image_path && File.exist?(full_path)
    bot.api.send_photo(
      chat_id: chat_id,
      photo: Faraday::UploadIO.new(full_path, "image/png"),
      caption: text,
      reply_markup: MAIN_MENU
    )
  else
    bot.api.send_message(chat_id: chat_id, text: text, reply_markup: MAIN_MENU)
  end
end

# --- ИНИЦИАЛИЗАЦИЯ ---
$users_data = load_data

TOKEN = ENV['TELEGRAM_BOT_TOKEN']

MAIN_MENU = Telegram::Bot::Types::ReplyKeyboardMarkup.new(
  keyboard: [
    [Telegram::Bot::Types::KeyboardButton.new(text: "Создать задачу"),
     Telegram::Bot::Types::KeyboardButton.new(text: "Мои задачи")],
    [Telegram::Bot::Types::KeyboardButton.new(text: "Помощь")]
  ],
  resize_keyboard: true
)

CANCEL_MENU = Telegram::Bot::Types::ReplyKeyboardMarkup.new(
  keyboard: [[Telegram::Bot::Types::KeyboardButton.new(text: "Отменить создание задачи")]],
  resize_keyboard: true
)

# --- ОСНОВНОЙ ЦИКЛ ---
if __FILE__ == $0
Telegram::Bot::Client.run(TOKEN) do |bot|
  bot.api.delete_webhook
  puts "Бот-напоминалка запущен..."
  start_scheduler(bot)

  bot.listen do |update|
    puts "Получено событие типа: #{update.class}"

    # НУЖНО ДОБАВИТЬ ЭТУ СТРОКУ:
    case update 
    when Telegram::Bot::Types::CallbackQuery
      puts "Нажата кнопка с данными: #{update.data}"
      bot.api.answer_callback_query(callback_query_id: update.id)

      if update.data.start_with?("delete_task_")
        task_id = update.data.sub("delete_task_", "")
        if delete_task_by_id(update.from.id, task_id)
          bot.api.edit_message_text(
            chat_id: update.message.chat.id,
            message_id: update.message.message_id,
            text: "✅ Задача удалена"
          )
        end
      end

    when Telegram::Bot::Types::Message
      next unless update.text
      uid = update.from.id
      $users_data[uid] ||= { tasks: [], status: nil, current_task: {} }
      user = $users_data[uid] # Обязательно объявляем user

      case update.text
      when "/start", "Отменить создание задачи"
        user[:status] = nil
        send_main_menu(bot, update.chat.id, "Привет! 
Я - бот-напоминалка, напишите мне задачу, поставьте время напоминания и я вам напомню! 
С чего начнём?", "res/notificatorStart.png")

      when "Помощь", "/help"
        bot.api.send_message(chat_id: update.chat.id, text: "Основные функции: 
/start - начать общение 
/help - получить помощь 
/MyTasks - получить список действующих задач 
/createTask - создать задание. Запишите задачу, которую нужно напомнить, дату и готово! 

Если вам чужды такие команды, можете воспользоваться быстрыми ответами внизу чата")

      when "Создать задачу", "/createTask"
        user[:status] = :wait_for_title
        bot.api.send_message(chat_id: update.chat.id, text: "Напишите в чат свою задачу", reply_markup: CANCEL_MENU)

      when "Мои задачи", "/MyTasks"
        if user[:tasks].empty?
          bot.api.send_message(chat_id: update.chat.id, text: "Задач еще нет. Создайте новую прямо сейчас!")
        else
          bot.api.send_message(chat_id: update.chat.id, text: "Ваши задачи:")
          user[:tasks].each do |t|
            kb = [[Telegram::Bot::Types::InlineKeyboardButton.new(text: "❌ Удалить задачу", callback_data: "delete_task_#{t[:id]}")]]
            markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: kb)
            bot.api.send_message(
              chat_id: update.chat.id,
              text: " #{t[:date].strftime("%d.%m.%y %H:%M")} — #{t[:title]}",
              reply_markup: markup
            )
          end
        end

      else
        case user[:status]
        when :wait_for_title
          user[:current_task][:title] = update.text
          user[:status] = :wait_for_date
          bot.api.send_message(chat_id: update.chat.id, text: "Введите дату: ДД.ММ.ГГГГ ЧЧ:ММ. \nПример: 31.12.2024 18:00")
        when :wait_for_date
          begin
            date = Time.strptime(update.text, "%d.%m.%Y %H:%M")
            if date < Time.now
              bot.api.send_message(chat_id: update.chat.id, text: "Вперед в прошлое! Введите дату еще раз:")
            else
              task_id = Time.now.to_f.to_s
              user[:tasks] << { id: task_id, title: user[:current_task][:title], date: date }
              user[:status] = nil
              save_data
              bot.api.send_message(chat_id: update.chat.id, text: "Отлично! Задача создана. Мы напомним вам о ней, чтобы вы не забыли выполнить!", reply_markup: MAIN_MENU)
            end
          rescue ArgumentError
            bot.api.send_message(chat_id: update.chat.id, text: "Ошибка формата. Нужно: 31.12.2024 18:00")
          end
        end
      end
    end # конец case update
  end
end
end

# Вынеси логику обработки сообщений в метод
def handle_message(bot, update)
  uid = update.from.id
  $users_data[uid] ||= { tasks: [], status: nil, current_task: {} }
  user = $users_data[uid]

  case update.text
  when "/start", "Отменить создание задачи"
    user[:status] = nil
    send_main_menu(bot, update.chat.id, "Продолжим?", "res/notificatorStart.png")
  when "Создать задачу"
    user[:status] = :wait_for_title
    bot.api.send_message(chat_id: update.chat.id, text: "Напишите в чат свою задачу")
  when "Мои задачи", "/MyTasks"
        if user[:tasks].empty?
          bot.api.send_message(chat_id: update.chat.id, text: "Задач еще нет. Создайте новую прямо сейчас!")
        else
          bot.api.send_message(chat_id: update.chat.id, text: "Ваши задачи:")
          user[:tasks].each do |t|
            kb = [[Telegram::Bot::Types::InlineKeyboardButton.new(text: "❌ Удалить задачу", callback_data: "delete_task_#{t[:id]}")]]
            markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: kb)
            bot.api.send_message(
              chat_id: update.chat.id,
              text: "📍 #{t[:date].strftime("%d.%m %H:%M")} — #{t[:title]}",
              reply_markup: markup
            )
          end
        end
  else
    # ВОТ ЭТОТ БЛОК ДОЛЖЕН БЫТЬ ЗДЕСЬ
    case user[:status]
    when :wait_for_title
      user[:current_task][:title] = update.text
      user[:status] = :wait_for_date
      bot.api.send_message(chat_id: update.chat.id, text: "Введите дату:")
    when :wait_for_date
        begin
          date = Time.strptime(update.text, "%d.%m.%Y %H:%M")
          if date < Time.now
            bot.api.send_message(chat_id: update.chat.id, text: "Дата в прошлом! Введите еще раз:")
          else
            task_id = Time.now.to_f.to_s
            user[:tasks] << { id: task_id, title: user[:current_task][:title], date: date }
            user[:status] = nil
            save_data
            bot.api.send_message(chat_id: update.chat.id, text: "✅ Сохранено!", reply_markup: MAIN_MENU)
          end
        rescue ArgumentError
        bot.api.send_message(chat_id: update.chat.id, text: "Ошибка формата. Нужно: 31.12.2024 18:00")
      end
    end
  end
end


# Вынеси логику планировщика (тело цикла) в метод
def check_due_tasks(bot)
  now = Time.now
  any_notified = false
  $users_data.each do |uid, data|
    due = data[:tasks].select { |t| t[:date] <= now }
    due.each do |task|
      bot.api.send_message(chat_id: uid, text: "⏰ НАПОМИНАНИЕ: #{task[:title]}")
      any_notified = true
    end
    data[:tasks].delete_if { |t| t[:date] <= now }
  end
  save_data if any_notified
end



# ruby lib/Telegram_Notificator_Bot.rb
