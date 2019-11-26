require 'rubygems'
require_relative './lib/louis_vuitton/stock_checker'
require_relative './lib/email_notifier'
require 'clockwork'
require 'active_support/time' # Allow numeric durations (eg: 1.minutes)
require 'twilio-ruby'

SKU_IDS=ENV.fetch('SKU_IDS').split(',')
COUNTRIES=ENV.fetch('COUNTRIES').split(',')

$logger = Logger.new(STDERR)
account_sid = ENV.fetch('TWILIO_ACCOUNT_SID')
auth_token = ENV.fetch('TWILIO_AUTH_TOKEN')
$client = Twilio::REST::Client.new account_sid, auth_token
$has_notified_list = {}

def notify_via_sms(body:)
  $client.messages.create(
    from: ENV.fetch('TWILIO_SENDER_PHONE_NUMBER'),
    to: ENV.fetch('TWILIO_RECEIVER_PHONE_NUMBER'),
    body: body)
end

def check_stock
  COUNTRIES.each do |country_code|
    stock_level = LouisVuitton::StockChecker.check_stock_for(sku_ids: SKU_IDS, country_code: country_code)

    SKU_IDS.each do |sku_id|
      stores = stock_level.fetch(country_code)
      stores.each do |store_lang, sku_details|
        if in_stock = !!sku_details.dig(sku_id, "inStock")
          $logger.warn "SKU: #{sku_id}, Country: #{country_code}, Store: #{store_lang}, In Stock: #{in_stock}"

          if $has_notified_list["#{sku_id}__#{store_lang}"].nil?
            $logger.warn "Notify user via SMS"
            notify_via_sms(body: "SKU: #{sku_id}, Country: #{country_code}, Store: #{store_lang}, In Stock: #{in_stock}")

            if email = ENV['NOTIFY_TO_EMAIl']
              $logger.warn "Notify user via email"
              EmailNotifier.new(email: email, subject: "SKU: #{sku_id}, Store: #{store_lang}, In Stock: #{in_stock}", body: "SKU: #{sku_id}, Store: #{store_lang}, In Stock: #{in_stock}")
            end

            $has_notified_list["#{sku_id}__#{store_lang}"] = true
          end
        end
      end
    end
  end
end

module Clockwork
  configure do |config|
    config[:logger] = $logger
  end

  handler do |command, time|
    case command
    when :check_stock
      check_stock
    when :clear_notified_list
      $has_notified_list = {}
    end
  end

  check_stock_frequency = ENV.fetch('STOCK_CHECK_FREQUENCY', 5).to_i.seconds
  notification_clear_frequency = ENV.fetch('NOTIFICATION_CLEAR_FREQUENCY', 7200).to_i.seconds

  every(check_stock_frequency, :check_stock)
  every(notification_clear_frequency, :clear_notified_list)
end
