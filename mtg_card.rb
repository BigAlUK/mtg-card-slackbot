#!/usr/bin/env ruby

require 'json'
require 'net/http'
require 'nokogiri'
require 'sinatra'
require 'sinatra/json'

def make_response(text, attachments = [], response_type = 'in_channel')
  {
    text: text,
    attachments: attachments,
    username: 'MTG Bot',
    icon_url: 'http://seeklogo.com/images/M\
               /magic-the-gathering-logo-E672A43B2E-seeklogo.com.gif',
    icon_emoji: '',
    response_type: response_type
  }
end

def card_urls(name, foil = false)
  uri = URI.parse('https://www.mtggoldfish.com/autocomplete')
  uri.query = URI.encode_www_form(term: "#{name} [")

  res = JSON.parse(Net::HTTP.get(uri))

  urls = res.map do |c|
    set = c['set'].gsub(/[^a-z0-9\s]/i, '').tr(' ', '+')
    name = c['name'].gsub(/[^a-z0-9\s]/i, '').tr(' ', '+')
    if foil
      next unless c['foil']
      next "https://www.mtggoldfish.com/price/#{set}:Foil/#{name}"
    else
      next if c['foil']
      next "https://www.mtggoldfish.com/price/#{set}/#{name}"
    end
  end

  urls.reject(&:nil?)
end

def low_price(name, foil = false)
  prices = card_urls(name, foil).map do |url|
    page = Nokogiri::HTML(Net::HTTP.get(URI.parse(url)))
    page.css('div.paper div.price-box-price').text.to_f
  end

  prices.select { |p| p > 0 }.min
end

def card_info(text)
  uri = URI.parse('https://api.deckbrew.com/mtg/cards')
  uri.query = URI.encode_www_form(name: text)
  data = JSON.parse(Net::HTTP.get(uri))
  card = data.find { |x| x['name'].casecmp(text.downcase).zero? }
  card = data.first if card.nil?

  if card.nil?
    return make_response("Could not match `#{text}` to any cards.",
                         'ephemeral')
  end

  cost = {
    title: 'Cost',
    value: card['cost'],
    short: true
  } unless card['cost'].empty?

  type_text = ''
  card['supertypes'].each do |t|
    type_text << "#{t.capitalize} "
  end unless card['supertypes'].nil?

  card['types'].each do |t|
    type_text << "#{t.capitalize} "
  end unless card['types'].nil?

  type_text << '- ' unless card['subtypes'].nil?

  card['subtypes'].each do |t|
    type_text << "#{t.capitalize} "
  end unless card['subtypes'].nil?

  type = {
    title: 'Type',
    value: type_text.strip,
    short: true
  }

  card_text = nil
  card_text = {
    title: 'Card Text',
    value: card['text'],
    short: false
  } unless card['text'].empty?

  p_t = nil
  p_t = {
    title: 'P/T',
    value: "#{card['power']}/#{card['toughness']}",
    short: true
  } unless card['power'].nil? || card['toughness'].nil?

  loyalty = nil
  loyalty = {
    title: 'Loyalty',
    value: card['loyalty'],
    short: true
  } unless card['loyalty'].nil?

  rarity = {
    title: 'Rarity',
    value: card['editions'].last['rarity'].capitalize,
    short: true
  }

  price = {
    title: 'Price',
    value: "$#{low_price(card['name'])}",
    short: true
  }

  fields = []
  fields << cost
  fields << type
  fields << card_text
  fields << p_t unless p_t.nil?
  fields << loyalty unless loyalty.nil?
  fields << rarity
  fields << price

  attachments = [{
    title: card['name'],
    fields: fields,
    image_url: card['editions'].max_by { |e| e['multiverse_id'] }['image_url']
  }]

  make_response('', attachments)
end

def combo_info(cards)
  attachments = []
  cards.each do |card_name|
    card_name.strip!
    uri = URI.parse('https://api.deckbrew.com/mtg/cards')
    uri.query = URI.encode_www_form(name: card_name)
    data = JSON.parse(Net::HTTP.get(uri))
    card = data.first

    if card.nil?
      return make_response("Could not match `#{card_name}` to any cards.",
                           'ephemeral')
    end

    attachments << {
      title: card['name'],
      image_url: card['editions'].last['image_url']
    }
  end

  make_response('Combo', attachments)
end

def pick_colours(names, colour_count)
  colours = [':mtg_mountain: Red', ':mtg_island: Blue', ':mtg_swamp: Black', ':mtg_forest: Green', ':mtg_plains: White']
  result = ''.tap do |str|
    names.sort.each do |name|
      str << "#{name.strip} you must build a deck with #{colours.sample(colour_count).join(' and ')}\n"
    end
  end
  make_response("The draw:\n" + result).to_json
end

post '/card' do
  cards = params['text'].split '+'
  if cards.length == 1
    json card_info(cards.first)
  else
    json combo_info(cards)
  end
end

post '/assign_colours' do
  names = params['text'].split ','
  colour_count = (names.last.to_i == 0) ? 1 : names.pop.to_i
  pick_colours(names, colour_count)
end
