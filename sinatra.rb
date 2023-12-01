# frozen_string_literal: true

require 'sinatra'
require 'sequel'
require 'sqlite3'
require 'json'

require_relative 'service'
helpers Service

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

  def to_responce
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

  def to_responce
    responce = to_hash
    responce.each_pair {|key, value| responce[key] = value.to_f if value.class == BigDecimal}
    responce
  end
end

before do
  content_type :json

  if request.request_method == 'POST' and request.content_type=='application/json'
    body_parameters = request.body.read
    parsed = body_parameters && body_parameters.length >= 2 ? JSON.parse(body_parameters) : nil
    params.merge!(parsed)
  end
end

post '/operation' do
  user = User.first(id: params[:user_id])
  return 'Пользователь не найден' if user.nil?

  positions = params[:positions]
  products = Product.where(id: positions.map{ |p| p[:id]} )

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

    product_to_position(product, position)
    product_discount(product, position, position_summ, user)
    product_cashback(product, position, position_summ, user, cashback)

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
    user: user.to_responce,
    operation_id: operation.id,
    summ:,
    positions:,
    discount:,
    cashback:,
  }.to_json
end

post '/submit' do
  user = User.first(id: params[:user][:id])
  return 'Пользователь не найден' if user.nil?

  operation = Operation.first(id:params[:operation_id])
  return 'Операция не найдена' if operation.nil?
  return 'Пользователю не принадлежит эта операция' if operation.user_id != params[:user][:id]
  return 'Операция уже выполнена' if operation.done

  if operation.allowed_write_off >= params[:write_off] 
    operation_transaction(user, operation, params[:write_off])
  else
    operation_transaction(user, operation, operation.allowed_write_off)
  end

  {
    status: 200,
    message:'Операция успешно выполнена',
    operation: operation.to_responce
  }.to_json
end
