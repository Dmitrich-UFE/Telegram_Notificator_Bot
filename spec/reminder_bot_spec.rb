require 'reminder_bot'

RSpec.describe ReminderBot do
  let(:api) { double('TelegramApi') }
  let(:bot) { ReminderBot.new(api) }
  let(:user_id) { 123 }

  before do
    allow(api).to receive(:send_message)
  end

  describe '#handle_message' do
    it 'переводит пользователя в состояние ожидания названия при создании задачи' do
      message = double('Message', text: 'Создать задачу', from: double(id: user_id), chat: double(id: user_id))
      
      bot.handle_message(message)
      
      expect(bot.users_data[user_id][:status]).to eq(:wait_for_title)
    end

    it 'сохраняет название задачи и просит дату' do
      bot.users_data[user_id] = { tasks: [], status: :wait_for_title, current_task: {} }
      message = double('Message', text: 'Купить молоко', from: double(id: user_id), chat: double(id: user_id))
      
      expect(api).to receive(:send_message).with(hash_including(text: 'Введите дату:'))
      bot.handle_message(message)
      
      expect(bot.users_data[user_id][:current_task][:title]).to eq('Купить молоко')
      expect(bot.users_data[user_id][:status]).to eq(:wait_for_date)
    end
  end

  describe 'Оповещения (Scheduler)' do
    it 'отправляет сообщение, если время задачи наступило' do
      # Создаем задачу в прошлом
      bot.users_data[user_id] = { 
        tasks: [{ title: 'Проснись!', date: Time.now - 10, id: '1' }] 
      }
      
      expect(api).to receive(:send_message).with(hash_including(text: /Проснись!/))
      
      bot.check_tasks
      
      # Проверяем, что задача удалилась после отправки
      expect(bot.users_data[user_id][:tasks]).to be_empty
    end
  end
end

# rspec spec/reminder_bot_spec.rb
