#!/usr/bin/env ruby
# encoding: utf-8
# This file is part of the K5 bot project.
# See files README.md and COPYING for copyright and licensing information.

# KANJIDIC2 converter
#
# Converts the KANJIDIC2 file to a marshalled hash, readable by the KANJIDIC2 plugin.
# When there are changes to KANJIDICEntry or KANJIDIC2 is updated, run this script
# to re-index (./convert.rb), then reload the KANJIDIC2 plugin (!load KANJIDIC2).

require 'nokogiri'

require_relative 'KANJIDIC2Entry'

class KANJIDICConverter
  attr_reader :hash

  def initialize(kanjidic_file)
    @kanjidic_file = kanjidic_file

    @kanji = {}
    @code_skip = {}
    @stroke_count = {}

    @hash = {}
    @hash[:kanji] = @kanji
    @hash[:code_skip] = @code_skip
    @hash[:stroke_count] = @stroke_count
  end

  def read
    reader = Nokogiri::XML::Reader(File.open(@kanjidic_file, 'r'))

    reader.each do |node|
      if node.node_type.eql?(Nokogiri::XML::Reader::TYPE_ELEMENT) && 'character'.eql?(node.name)
        parsed = Nokogiri::XML(node.outer_xml)

        entry = KANJIDIC2Entry.new()
        fill_entry(entry, parsed.child)

        @kanji[entry.kanji] = entry
        entry.code_skip.each do |skip|
          put_to_radical_group(@code_skip, skip, entry)
        end
        put_to_radical_group(@stroke_count, entry.stroke_count.to_s, entry)
      end
    end
  end

  private

  def fill_entry(entry, node)
    entry.kanji = node.css('literal').first.text
    entry.radical_number = node.css('radical rad_value[rad_type="classical"]').first.text.to_i

    entry.code_skip = node.css('query_code q_code[qc_type="skip"]').map {|n| n.text.strip}

    misc = node.css('misc').first

    grade = misc.css('grade').first
    entry.grade = grade ? grade.text.to_i : nil

    raise "Unknown kanji grade: #{entry.grade}" unless entry.grade.nil? || (1..10).include?(entry.grade)

    entry.stroke_count = misc.css('stroke_count').first.text.to_i

    freq = misc.css('freq').first
    entry.freq = freq ? freq.text.to_i : nil

    reading_meaning = node.css('reading_meaning').first

    unless reading_meaning
      entry.readings = entry.meanings = {}
      return
    end

    rm_groups = reading_meaning.css('rmgroup')
    case rm_groups.size
    when 0
      raise "Error in entry #{entry.kanji}. 'reading_meaning' node must contain one 'rmgroup' node."
    when 1
      # (pinyin) shen2 (korean_r) sin (korean_h) 신 (ja_on) シン ジン (ja_kun) かみ かん- こう-
      entry.readings = rm_groups.first.css('reading').each_with_object(Hash.new) do |reading, hash|
        key = reading['r_type'].to_sym
        txt = reading.text
        txt = txt.strip.split(' ')
        hash[key] ||= []
        hash[key] |= (txt)
      end

      # :korean_r is a waste of space, b/c it's not always correct,
      # and we can recompute it from korean_h. removing it.
      entry.readings.delete(:korean_r)

      reading_meaning.css('nanori').each_with_object(entry.readings) do |n, hash|
        hash[:nanori] ||= []
        hash[:nanori] << n.text.strip
      end

      entry.meanings = reading_meaning.css('meaning').each_with_object(Hash.new) do |meaning, hash|
        lang = meaning['m_lang'] || :en
        key = lang.to_sym
        txt = meaning.text.strip
        hash[key] ||= []
        hash[key] << txt
      end

      # we don't actually use other languages yet. free some memory.
      entry.meanings.delete_if {|lang, _| lang != :en}
    else
      raise "This plugin should be rewritten to properly display more than one reading/meaning group."
    end
  end

  def put_to_radical_group(hash, key, entry)
    hash[key] ||= {}
    hash[key][entry.radical_number] ||= []
    hash[key][entry.radical_number] << entry
  end
end

def marshal_dict(dict)
  ec = KANJIDICConverter.new("#{(File.dirname __FILE__)}/#{dict}.xml")

  print "Indexing #{dict.upcase}..."
  ec.read
  puts "done."

  print "Marshalling #{dict.upcase}..."
  File.open("#{(File.dirname __FILE__)}/#{dict}.marshal", 'w') do |io|
    Marshal.dump(ec.hash, io)
  end
  puts "done."
end

marshal_dict('kanjidic2')
