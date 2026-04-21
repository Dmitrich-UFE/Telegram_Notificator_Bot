require 'rspec'
require 'telegram/bot'
require_relative '../lib/Telegram_Notificator_Bot'

RSpec.describe 'Telegram Notificator Bot' do
  let(:bot) { double('bot') }
  let(:api) { double('api') }
  let(:chat_id) { 123456 }

  before do
    allow(bot).to receive(:api).and_return(api)
    allow(api).to receive(:send_message)
    allow(api).to receive(:send_photo)
    $users_data = {} 
    # Заглушаем сохранение в файл, чтобы не плодить мусор при тестах
    allow_any_instance_of(Object).to receive(:save_data) 
  end

  it 'отправляет приветствие и меню при команде /start' do
    # Используем обычный double, так как instance_double может быть слишком строгим
    message = double('message', 
                      text: '/start', 
                      chat: double(id: chat_id),
                      from: double(id: chat_id, first_name: 'TestUser'))

    expect(api).to receive(:send_photo).with(hash_including(chat_id: chat_id))
    handle_message(bot, message) 
  end

  it 'создает задачу и сохраняет её в памяти' do
    # 1. Устанавливаем начальное состояние: бот ждет название
    $users_data[chat_id] = { tasks: [], status: :wait_for_title, current_task: {} }
    
    # 2. Имитируем ввод названия пользователем
    # Важно: используем double, который отвечает на .text и .from.id
    message = double('message', 
                     text: 'Купить молоко', 
                     from: double(id: chat_id), 
                     chat: double(id: chat_id))
    
    # Заглушаем отправку сообщения "Введите дату", чтобы тест не упал
    allow(api).to receive(:send_message) 

    # 3. Вызываем обработчик
    handle_message(bot, message)
    
    # 4. Проверяем результат
    # Проверьте, что в основном коде данные пишутся именно в :current_task
    expect($users_data[chat_id][:current_task][:title]).to eq('Купить молоко')
    expect($users_data[chat_id][:status]).to eq(:wait_for_date)
  end


  it 'удаляет задачу по ID' do
    task_id = "test_123"
    $users_data[chat_id] = { tasks: [{ id: task_id, title: 'Удалить меня' }] }
    
    delete_task_by_id(chat_id, task_id)
    
    expect($users_data[chat_id][:tasks]).to be_empty
  end

  it 'планировщик находит задачи, время которых наступило' do
    past_time = Time.now - 10
    $users_data[chat_id] = { tasks: [{ id: '1', title: 'Срочно!', date: past_time }] }
  
    expect(api).to receive(:send_message).with(hash_including(text: /Срочно!/))
    
    check_due_tasks(bot) 
  end
end


# rspec spec/bot_spec.rb
