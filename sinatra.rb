require 'sinatra'
require 'sequel'
require 'sqlite3'
require 'json'
require 'pry'
require 'pry-nav'

require_relative 'product_helper'

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

  def user_responce
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
    'discount': "Дополнительная скидка 15%",
    'noloyalty':'Не участвует в системе лояльности',
}.freeze

  def description
    DESCRIPTION[type]
  end
end

class Operation < Sequel::Model
  many_to_one :user
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
  cashback = {
            existed_summ: user.bonus.to_f,
            allowed_summ: 0.0,
            will_add: 0.0
        }
  summ = 0.0
  discount = { summ: 0.0 }

  positions.each do |position|
    product = Product.first(id: position[:id])
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
    write_off: cashback[:allowed_summ],
    check_summ: summ,
    done: false,
    allowed_write_off: )

  responce = {
    status: 200,
    user: user.user_responce,
    operation_id: operation.id,
    summ:,
    positions:,
    discount:,
    cashback:,
}.to_json
end

get '/test/:id' do
  puts params[:id]
end

# a = {
#     "status": 200,
#     "user": {
#         "id": 1,
#         "template_id": 1,
#         "name": "Иван",
#         "bonus": "9370.0"
#     },
#     "operation_id": 29,
#     "summ": 734.0,
#     "positions": [
#         {
#             "id": 1,
#             "price": 100,
#             "quantity": 3,
#             "type": null,
#             "value": null,
#             "type_desc": null,
#             "discount_percent": 0.0,
#             "discount_summ": 0.0
#         },
#         {
#             "id": 2,
#             "price": 50,
#             "quantity": 2,
#             "type": "increased_cashback",
#             "value": "10",
#             "type_desc": "Дополнительный кэшбек 10%",
#             "discount_percent": 0.0,
#             "discount_summ": 0.0
#         },
#         {
#             "id": 3,
#             "price": 40,
#             "quantity": 1,
#             "type": "discount",
#             "value": "15",
#             "type_desc": "Дополнительная скидка 15%",
#             "discount_percent": 15.0,
#             "discount_summ": 6.0
#         },
#         {
#             "id": 4,
#             "price": 150,
#             "quantity": 2,
#             "type": "noloyalty",
#             "value": null,
#             "type_desc": "Не участвует в системе лояльности",
#             "discount_percent": 0.0,
#             "discount_summ": 0.0
#         }
#     ],
#     "discount": {
#         "summ": 6.0,
#         "value": "0.81%"
#     },
#     "cashback": {
#         "existed_summ": 9370,
#         "allowed_summ": 434.0,
#         "value": "4.19%",
#         "will_add": 31
#     }
# }