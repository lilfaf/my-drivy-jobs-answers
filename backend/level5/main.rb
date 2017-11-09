require 'json'
require 'date'
require 'singleton'
require 'forwardable'

# Shared data source
class JsonSource
  include Singleton

  attr_reader :options

  DEFAULT_OPTIONS = {
    src_path: './data.json'
  }.freeze

  def initialize(options = {})
    @options = DEFAULT_OPTIONS.merge(options)
  end

  def data
    @data ||= JSON.parse(json)
  end

  def json
    File.read(options[:src_path])
  end
end

# Base model
class Model
  extend Forwardable

  attr_reader :adapter

  def initialize(adapter = :json)
    @adapter = case adapter
               when :json
                 JsonSource.instance
               end
  end

  def_delegators :@adapter, :data

  def assign_params(params = {})
    params.each do |attribute, value|
      send("#{attribute}=", value) if respond_to?(attribute)
    end
    self
  end
end

# Car model
class Car < Model
  attr_accessor :id,
                :price_per_day,
                :price_per_km

  def self.all
    @all ||= new.data['cars'].each_with_object([]) do |rental, arr|
      arr << new.assign_params(rental)
    end
  end

  def self.find_by_id(id)
    all.select { |car| car.id == id }.first
  end
end

# Rental model
class Rental < Model
  # Values in percentage
  DISCOUNT_PER_DAY = {
    '1'  => 10,
    '4'  => 30,
    '10' => 50
  }.freeze

  attr_accessor :id,
                :car_id,
                :start_date,
                :end_date,
                :distance

  def time_period_in_days
    @days ||= (Date.parse(end_date) - Date.parse(start_date)).round
  end

  def price
    car = Car.find_by_id(car_id)
    car_price_per_day = car.price_per_day
    DISCOUNT_PER_DAY.each do |key, value|
      next unless time_period_in_days > key.to_i
      car_price_per_day = (car_price_per_day / value) * 100
    end
    period_price = time_period_in_days * car_price_per_day
    distance_price = distance * car.price_per_km
    period_price + distance_price
  end

  def self.all
    @all ||= new.data['rentals'].each_with_object([]) do |rental, arr|
      arr << new.assign_params(rental)
    end
  end

  def self.find_by_id(id)
    all.select { |rental| rental.id == id }.first
  end
end

# Holds commisions caculations
class Commission
  ASSISTANCE_FEE_PER_DAY = 1
  DEDUCTIBLE_REDUCTION_FEE = 4

  attr_reader :rental, :insurrance_fee, :assistance_fee, :drivy_fee

  def initialize(rental)
    @rental = rental
  end

  def insurrance_fee
    @insurrance_fee ||= rental.price / 2
  end

  def assistance_fee
    @assistance_fee ||= ASSISTANCE_FEE_PER_DAY * rental.time_period_in_days
  end

  def drivy_fee
    @diry_fee ||= rental.price - insurrance_fee - assistance_fee
  end

  def deductible_reduction_fee
    @dr_fee ||= rental.time_period_in_days * DEDUCTIBLE_REDUCTION_FEE
  end

  def total_fee
    insurrance_fee + assistance_fee + drivy_fee
  end

  def to_h
    {
      insurrance_fee: insurrance_fee,
      assistance_fee: assistance_fee,
      drivy_fee: drivy_fee
    }
  end
end

ACTORS = %i(driver owner insurance assistance drivy).freeze

# Fee calculations
module ActorsFee
  def self.amount(actor, rental, commission)
    case actor
    when :driver
      rental.price + commission.deductible_reduction_fee
    when :owner
      rental.price - commission.total_fee
    when :insurance
      commission.insurrance_fee
    when :assistance
      commission.assistance_fee
    when :drivy
      commission.drivy_fee + commission.deductible_reduction_fee
    end
  end
end

# Main runner
module Main
  def self.do_the_job
    # Build JSON hash
    rentals = Rental.all.each_with_object([]) do |rental, arr|
      rental = Rental.find_by_id(rental.id)
      commission = Commission.new(rental)
      arr << {
        id: rental.id,
        actions: ACTORS.map { |actor|
          {
            who: actor,
            type: actor == :driver ? 'debit' : 'credit',
            amout: ActorsFee.amount(actor, rental, commission)
          }
        }
      }
      arr
    end

    # Write to JSON output
    File.open('./foobar.json', 'w') do |f|
      f.write(JSON.pretty_generate(rentals: rentals))
    end
  end
end

Main.do_the_job
