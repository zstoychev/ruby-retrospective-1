require 'bigdecimal'
require 'bigdecimal/util'
require 'singleton'

module Promotions
  class None
    def discount_for(price, count)
      0
    end
  end

  class GetOneFree
    attr_reader :promotion_count
    
    def initialize(promotion_count)
      @promotion_count = promotion_count
    end
    
    def discount_for(price, count)
      price * (count / promotion_count)
    end
  end

  class Package
    attr_reader :promotion_count, :percent
    
    def initialize(promotion_count_to_percent)
      @promotion_count, @percent = promotion_count_to_percent.first
    end
    
    def discount_for(price, count)
      price * promotion_count * (count / promotion_count) * percent / '100'.to_d
    end
  end

  class Threshold
    attr_reader :threshold, :percent

    def initialize(threshold_to_percent)
      @threshold, @percent = threshold_to_percent.first
    end
    
    def discount_for(price, count)
      price * [(count - threshold), 0].max * percent / '100'.to_d
    end
  end
end

class Product
  PROMOTION_TYPE_TO_CLASS = {
    none: Promotions::None,
    get_one_free: Promotions::GetOneFree,
    package: Promotions::Package,
    threshold: Promotions::Threshold,
  }
  
  attr_reader :name, :price, :promotion
  
  def initialize(name, price, promotion)
    raise "Product's name must be at most 40 symbols." unless name.size <= 40
    unless price.to_d >= '0.01'.to_d and price.to_d <= '999.99'.to_d
      raise "Price must be between 0.01 and 999.99."
    end

    @name = name
    @price = price.to_d
    promotion_type, promotion_value = promotion.first
    @promotion = PROMOTION_TYPE_TO_CLASS[promotion_type].new(promotion_value)
  end

  def price_for(count)
    price_without_discount_for(count) - discount_for(count)
  end
  
  def price_without_discount_for(count)
    price * count
  end
  
  def discount_for(count)
    promotion.discount_for(price, count)
  end
end

module Coupons
  class None
    def name
      "NONE"
    end
    
    def discount_for(price)
      0
    end
  end

  class Percent
    attr_reader :name, :percent
    
    def initialize(name, percent)
      @name, @percent = name, percent
    end
    
    def discount_for(price)
      price * percent / '100'.to_d
    end
  end

  class Amount
    attr_reader :name, :amount
    
    def initialize(name, amount)
      @name, @amount = name, amount.to_d
    end
    
    def discount_for(price)
      [price, amount].min
    end
  end
end

class Inventory
  COUPON_TYPE_TO_CLASS = {
    percent: Coupons::Percent,
    amount: Coupons::Amount,
  }
  
  def initialize
    @name_to_product = {}
    @name_to_coupon = {}
  end
  
  def register(product_name, price, promotion = {none: nil})
    @name_to_product[product_name] = Product.new(product_name, price, promotion)
  end
  
  def register_coupon(coupon_name, coupon)
    type, value = coupon.first
    coupon = COUPON_TYPE_TO_CLASS[type].new(coupon_name, value)
    @name_to_coupon[coupon_name] = coupon
  end 
  
  def new_cart
    Cart.new self
  end 
  
  def get_product(product_name)
    @name_to_product[product_name] or raise "Unknown product"
  end
  
  def get_coupon(coupon_name)
    @name_to_coupon[coupon_name] or raise "Unknown coupon"
  end
end

class CartItem
  attr_reader :product
  attr_accessor :count
  
  def initialize(product, count)
    @product = product
    @count = 0
    self.count = count
  end
  
  def count=(count)
    unless count >= 0 and self.count + count < 100
      raise "A product's count must be between 0 and 99."
    end
    
    @count = count
  end
  
  def price
    product.price_for count
  end
  
  def price_without_discount
    product.price_without_discount_for count
  end
  
  def discount
    product.discount_for count
  end
  
  def discounted?
    discount.nonzero?
  end
end

class Cart
  attr_reader :inventory, :used_coupon

  def initialize(inventory)
    @inventory = inventory
    @name_to_items = Hash.new do |hash, name|
      hash[name] = CartItem.new(inventory.get_product(name), 0)
    end
    @used_coupon = Coupons::None.new
  end
  
  def items
    @name_to_items.values
  end
  
  def add(product_name, count = 1)
    raise "Count must be greater than 0." unless count > 0
    
    @name_to_items[product_name].count += count
  end
  
  def use(coupon_name)
    @used_coupon = inventory.get_coupon coupon_name
  end
  
  def total
    total_without_coupon_discount - coupon_discount
  end
  
  def total_without_coupon_discount
    items.map(&:price).inject(&:+)
  end
  
  def coupon_discount
    used_coupon.discount_for total_without_coupon_discount
  end
  
  # def coupon_discounted?
  #   coupon_discount.nonzero?
  # end
  
  def invoice(invoice_maker = DefaultInvoice::InvoiceMaker.new)
    invoice_maker.make_invoice_of(self)
  end
end

class ElementColumn
  attr_reader :width, :align
  
  def initialize(width, align)
    @width, @align = width, align
  end
  
  def align_as_sprintf_sign
    align == :left ? "-" : ""
  end
end

class Separator
  include Singleton
  
  def intersect_with(column)
    case column
      when Separator then "+"
      else "-" * (column.width + 2)
    end
  end
  
  def to_text(columns)
    columns.map { |column| intersect_with column }.join ""
  end
end

class ElementRow
  def initialize(elements)
    @elements = elements
  end
  
  def intersect_with(column)
    case column
      when Separator then "|"
      else " %#{column.align_as_sprintf_sign}#{column.width}s "
    end
  end
  
  def to_text(columns)
    columns.map { |column| intersect_with column }.join("") % @elements
  end
end

class SimpleTable
  def initialize(columns)
    @columns = add_border(columns)
    @rows = []
  end
  
  def add_row(elements)
    @rows << ElementRow.new(elements)
  end
  
  alias << add_row
  
  def add_horizontal_separator
    @rows << Separator.instance
  end
  
  def to_text
    rows_as_text = add_border(@rows).map { |row| row.to_text(@columns) }
    rows_as_text.join("\n") + "\n"
  end
  
  private
  
  def add_border(table_part)
    [Separator.instance] + table_part + [Separator.instance]
  end
end

module NumberUtils
  def self.ordinal_suffix_of(number)
    return "th" if (11..19).include? number
    
    case number % 10
      when 1 then "st"
      when 2 then "nd"
      when 3 then "rd"
      else "th"
    end
  end
  
  def self.as_ordinal(number)
    "#{number}#{ordinal_suffix_of number}"
  end
end

module DefaultInvoice
  module English
    class GetOneFreePromotionDescriptor
      def description_of(promotion)
        "buy #{promotion.promotion_count - 1}, get 1 free"
      end
    end
    
    class PackagePromotionDescriptor
      def description_of(promotion)
        "get #{promotion.percent}% off for every #{promotion.promotion_count}"
      end
    end
    
    class ThresholdPromotionDescriptor
      def description_of(promotion)
        threshold_as_ordinal = NumberUtils.as_ordinal promotion.threshold
        "#{promotion.percent}% off of every after the #{threshold_as_ordinal}"
      end
    end
    
    class ElementsFormatter
      include Singleton
      
      def header_row
        ["Name", "qty", "price"]
      end
      
      def total_row(cart)
        ["TOTAL", "", format_decimal(cart.total)]
      end
      
      def promotion_row(promotion, discount)
        promotion_description = get_promotion_description promotion
        ["  (#{promotion_description})", "", format_decimal(discount)]
      end
      
      def item_row(name, count, price)
        [name, count, format_decimal(price)]
      end
      
      def coupon_row(coupon, discount)
        coupon_description = get_coupon_description coupon
        [
          "Coupon #{coupon.name} - #{coupon_description}",
          "",
          format_decimal(-discount)
        ]
      end
      
      private
      
      PROMOTION_TO_DESCRIPTOR = {
        Promotions::GetOneFree => GetOneFreePromotionDescriptor.new,
        Promotions::Package => PackagePromotionDescriptor.new,
        Promotions::Threshold => ThresholdPromotionDescriptor.new,
      }
      
      def get_promotion_description(promotion)
        if not PROMOTION_TO_DESCRIPTOR.include?(promotion.class)
          return 'unknown promotion'
        end
        
        PROMOTION_TO_DESCRIPTOR[promotion.class].description_of(promotion)
      end
      
      def get_coupon_description(coupon)
        case coupon
          when Coupons::Percent
            "#{coupon.percent}% off"
          when Coupons::Amount
            "#{format_decimal coupon.amount} off"
          else
            "unknown coupon"
        end
      end
      
      def format_decimal(number)
        "%.2f" % number
      end
    end
  end

  class InvoiceMaker
    def initialize(elements_formatter = English::ElementsFormatter.instance)
      @formatter = elements_formatter
    end
    
    def make_invoice_of(cart)
      table = create_table
      
      add_header table
      #table.add_horizontal_separator
      add_items table, cart
      add_coupon_info table, cart
      #table.add_horizontal_separator
      add_total table, cart
      
      table.to_text
    end
    
    private
    
    def create_table
      columns = [
        ElementColumn.new(40, :left),
        ElementColumn.new(4, :right),
        Separator.instance,
        ElementColumn.new(8, :right),
      ]
      
      SimpleTable.new(columns)
    end
    
    def add_header(table)
      table << @formatter.header_row
      table.add_horizontal_separator
    end
    
    def add_total(table, cart)
      table.add_horizontal_separator
      table << @formatter.total_row(cart)
    end
    
    def add_promotion_row(table, item)
      if item.discounted?
        discount = -item.discount
        table << @formatter.promotion_row(item.product.promotion, discount)
      end
    end
    
    def add_items(table, cart)
      cart.items.each do |item|
        price = item.price_without_discount
        table << @formatter.item_row(item.product.name, item.count, price)
        add_promotion_row(table, item) # if item.discounted?
      end
    end
    
    def add_coupon_info(table, cart)
      if cart.coupon_discount.nonzero?
        table << @formatter.coupon_row(cart.used_coupon, cart.coupon_discount)
      end
    end
  end
end
