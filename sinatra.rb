require 'sinatra'
require 'sequel'
require 'sqlite3'
require 'json'
require 'pry'
require 'pry-nav'

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
end

class Template < Sequel::Model
  one_to_many :users
end

class Product < Sequel::Model
  DESCRIPTION = {
    increased_cashback: 'Дополнительный кэшбек 10%',
    discount: "Дополнительная скидка 15%",
    noloyalty:'Не участвует в системе лояльности',
}.freeze

  def description
    DESCRIPTION[type.to_sym]
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
  discount_summ = 0.0

  positions.each do |position|
    product = Product.first(id: position[:id])
    position[:type] = product&.type
    position[:value] = product&.value
    position[:type_desc] = product&.description
    position[:discount_percent] = product&.value.to_f
    position_summ = position[:price] * position[:quantity]

    if product&.type == 'discount'
      position[:discount_percent] = product.value.to_f
      position[:discount_summ] = position_summ * (product.value.to_f / 100)
    elsif user.discount? && product&.type != 'noloyalty'
      position[:discount_percent] = user.template.discount.to_f
      position[:discount_summ] = position_summ * (user.template.discount.to_f / 100)
    else
      position[:discount_percent] = 0.0
      position[:discount_summ] = 0.0
    end

    if product&.type == 'increased_cashback'
      cashback[:will_add] += (position_summ - position[:discount_summ]) * (product.value.to_f / 100)
    end
    if user.cashback? && product&.type != 'noloyalty'
      cashback[:will_add] += (position_summ - position[:discount_summ]) * (user.template.cashback.to_f / 100)
    end

    if product&.type != 'noloyalty'
      cashback[:allowed_summ] += (position_summ - position[:discount_summ])
    end

    discount_summ += position[:discount_summ]
    summ += position[:price] * position[:quantity]
  end

  discount = {
    summ: discount_summ,
    value: (discount_summ/summ * 100).round(2).to_s + '%' 
  }

  cashback[:value] = (cashback[:will_add] * 100 / summ).round(2).to_s + '%' 

  summ -= discount_summ
  user_responce = user.to_hash
  user_responce[:bonus] = user_responce[:bonus].to_f
  responce = {
    status: 200,
    user: user.to_hash,
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