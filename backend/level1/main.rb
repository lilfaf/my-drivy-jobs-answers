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
  attr_accessor :id,
                :car_id,
                :start_date,
                :end_date,
                :distance

  def time_period_in_days
    (Date.parse(end_date) - Date.parse(start_date)).round
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

# Business logic
module RentalPricingService
  def self.price(rental_id)
    # Fetch data
    rental = Rental.find_by_id(rental_id)
    car = Car.find_by_id(rental.car_id)

    # Make calculation
    period_price = rental.time_period_in_days * car.price_per_day
    distance_price = rental.distance * car.price_per_km
    period_price + distance_price
  end
end

# Main runner
module Main
  def self.do_the_job
    # Build JSON hash
    rentals = Rental.all.each_with_object([]) do |rental, arr|
      arr << { id: rental.id, price: RentalPricingService.price(rental.id) }
      arr
    end

    # Write to JSON output
    File.open('./foobar.json', 'w') do |f|
      f.write(JSON.pretty_generate(rentals: rentals))
    end
  end
end

Main.do_the_job
