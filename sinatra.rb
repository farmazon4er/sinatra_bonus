# frozen_string_literal: true

require 'sinatra'
require 'sequel'
require 'sqlite3'
require 'json'
require 'pry'
require 'pry-nav'

require_relative 'service'

DB = Sequel.connect('sqlite://test.db')

class User < Sequel::Model
  many_to_one :template
  one_to_many :operations

  def cashback?
    template.name == 'Bronze' || template.name == 'Silver'
  end

  def discount?
    template.name == 'Gold' || template.name == 'Silver'
  end

  def responce
    responce = to_hash
    responce[:bonus] = responce[:bonus].to_f
    responce
  end
end

class Template < Sequel::Model
  one_to_many :users
end

class Product < Sequel::Model
  DESCRIPTION = {
    'increased_cashback': 'Дополнительный кэшбек 10%',
    'discount': 'Дополнительная скидка 15%',
    'noloyalty':'Не участвует в системе лояльности',
}.freeze

  def description
    DESCRIPTION[type]
  end
end

class Operation < Sequel::Model
  many_to_one :user

  def responce
    responce = to_hash
    responce[:cashback] = responce[:cashback].to_f
    responce[:discount] = responce[:discount].to_f
    responce[:write_off] = responce[:write_off].to_f
    responce[:check_summ] = responce[:check_summ].to_f
    responce[:allowed_write_off] = responce[:allowed_write_off].to_f
    responce
  end
end

before do
  content_type :json

  if request.request_method == "POST" and request.content_type=="application/json"
    body_parameters = request.body.read
    parsed = body_parameters && body_parameters.length >= 2 ? JSON.parse(body_parameters) : nil
    params.merge!(parsed)
  end
end

post '/operation' do
  user = User.first(id: params[:user_id])
  positions = params[:positions]
  products = Product.where(id: positions.map{|p| p[:id]})

  cashback = {
            existed_summ: user.bonus.to_f,
            allowed_summ: 0.0,
            will_add: 0.0
        }
  summ = 0.0
  discount = { summ: 0.0 }

  positions.each do |position|
    product = products[position[:id]]
    position_summ = position[:price] * position[:quantity]

    product_to_position(position, product)
    product_discount(position, position_summ, product, user)
    product_cashback(position, position_summ, product, user, cashback)

    discount[:summ] += position[:discount_summ]
    summ += position_summ
  end

  discount[:value] = to_percent(discount[:summ] / summ)
  cashback[:value] = to_percent(cashback[:will_add] / summ)
  summ -= discount[:summ]

  allowed_write_off = user.bonus > cashback[:allowed_summ] ? cashback[:allowed_summ] : user.bonus

  operation = Operation.create(
    user_id: user.id, 
    cashback: cashback[:will_add], 
    cashback_percent: cashback[:value],
    discount: discount[:summ], 
    discount_percent:discount[:value], 
    check_summ: summ,
    done: false,
    allowed_write_off:)

  {
    status: 200,
    user: user.responce,
    operation_id: operation.id,
    summ:,
    positions:,
    discount:,
    cashback:,
  }.to_json
end

post '/submit' do
  operation = Operation.first(id:params[:operation_id])
  return 'Операция уже выполнена' if operation&.done
  return 'Операция не найдена' if operation.nil?
  return 'Пользователю не принадлежит эта операция' if operation.user_id != params[:user][:id]
  user = User.first(id: params[:user][:id])

  if operation.allowed_write_off >= params[:write_off] 
    operation_transaction(user, operation, params[:write_off])
  else
    operation_transaction(user, operation, operation.allowed_write_off)
  end

  {
    status: 200,
    message:'Операция успешно выполнена',
    operation: operation.responce
  }.to_json
end
