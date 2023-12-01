# frozen_string_literal: true

def product_to_position(position, product)
  position[:type] = product&.type
  position[:value] = product&.value
  position[:type_desc] = product&.description
  position[:discount_percent] = product&.value.to_f
end

def product_discount(position, position_summ, product, user)
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
end

def product_cashback(position, position_summ, product, user, cashback)
  if product&.type == 'increased_cashback'
    cashback[:will_add] += (position_summ - position[:discount_summ]) * (product.value.to_f / 100)
  end
  if user.cashback? && product&.type != 'noloyalty'
    cashback[:will_add] += (position_summ - position[:discount_summ]) * (user.template.cashback.to_f / 100)
  end
  return unless product&.type != 'noloyalty'

  cashback[:allowed_summ] += (position_summ - position[:discount_summ])
end

def to_percent(value)
  "#{(value * 100).round(2)}%"
end
