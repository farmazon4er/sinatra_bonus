# frozen_string_literal: true

module Service
  def product_to_position(product, position)
    position[:type] = product&.type
    position[:value] = product&.value
    position[:type_desc] = product&.description
    position[:discount_percent] = product&.value.to_f
  end
  
  def product_discount(product, position, position_summ, user)
    if product&.type == 'discount'
      position[:discount_percent] = product.value.to_f
      position[:discount_summ] = position_summ * (position[:discount_percent] / 100)
    elsif user.discount? && product&.type != 'noloyalty'
      position[:discount_percent] = user.template.discount.to_f
      position[:discount_summ] = position_summ * (position[:discount_percent] / 100)
    else
      position[:discount_percent] = 0.0
      position[:discount_summ] = 0.0
    end
  end
  
  def product_cashback(product, position, position_summ, user, cashback)
    if product&.type == 'increased_cashback'
      cashback[:will_add] += (position_summ - position[:discount_summ]) * (product.value.to_f / 100)
    end
    if user.cashback? && product&.type != 'noloyalty'
      cashback[:will_add] += (position_summ - position[:discount_summ]) * (user.template.cashback.to_f / 100)
    end
    return if product&.type == 'noloyalty'
  
    cashback[:allowed_summ] += (position_summ - position[:discount_summ])
  end
  
  def to_percent(value)
    "#{(value * 100).round(2)}%"
  end
  
  def operation_transaction(user, operation, write_off)
    DB.transaction do
      write_off = user.bonus if (user.bonus - write_off).negative?
      user.bonus -= write_off
      user.bonus += operation.cashback
      user.save

      operation.check_summ -= write_off
      operation.done = true
      operation.write_off = write_off
      operation.save
    end
  end
end
