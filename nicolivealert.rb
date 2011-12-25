#!/usr/bin/ruby
# -*- coding: utf-8 -*-
#
# The MIT License (MIT)
# Copyright (c) 2011 heartnet
# Permission is hereby granted, free of charge, to any person obtaining a copy 
# of this software and associated documentation files (the "Software"), to 
# deal in the Software without restriction, including without limitation the 
# rights to use, copy, modify, merge, publish, distribute, sublicense, and/or 
# sell copies of the Software, and to permit persons to whom the Software is 
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in 
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL 
# THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER 
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING 
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER 
# DEALINGS IN THE SOFTWARE.

$: << File::dirname(__FILE__)
require 'rubygems'
require 'base64'
require 'socket'
require 'twitter'
require 'mechanize'
require 'rexml/document'

# Nico Live Account (Main)
NICO_MAIN_ID    ="YOUR_MAIN_NICONICO_ID_HERE"
NICO_MAIN_PASS  ="YOUR_MAIN_NICONICO_PASSWORD_HERE"

# Nico Live Account (Bot)
NICO_BOT_ID    ="YOUR_BOT_NICONICO_ID_HERE"
NICO_BOT_PASS  ="YOUR_BOT_NICONICO_PASSWORD_HERE"

# Twitter Oauth Info (Bot)
OAUTH_CONSUMER_KEY         ="OAUTH_CONSUMER_KEY_HERE"
OAUTH_COMSUMER_SECRET      ="OAUTH_COMSUMER_SECRET_HERE"
OAUTH_ACCESS_TOKEN         ="OAUTH_ACCESS_TOKEN_HERE"
OAUTH_ACCESS_TOKEN_SECRET  ="OAUTH_ACCESS_TOKEN_SECRET_HERE"

# Initialize Twitter Client
Twitter::configure do |config|
	config.consumer_key        =OAUTH_CONSUMER_KEY
	config.consumer_secret     =OAUTH_COMSUMER_SECRET
	config.oauth_token         =OAUTH_ACCESS_TOKEN
	config.oauth_token_secret  =OAUTH_ACCESS_TOKEN_SECRET
end

# Browser Emulation by Mechanize
mech             =Mechanize::new()
mech.user_agent  ="NicoLiveAlert 1.2.0"

bot             =Mechanize::new()
bot.user_agent  =""

# Login (Bot)
login_form  =bot.get("https://secure.nicovideo.jp/secure/login_form").forms.first
login_form.fields[1].value  =NICO_BOT_ID
login_form.fields[2].value  =NICO_BOT_PASS
redirected_page  =bot.submit(login_form)


# Request API 1 (Nico Live)
tk_rdata  =mech.post("https://secure.nicovideo.jp/secure/login?site=nicolive_antenna",
					"mail"      => NICO_MAIN_ID,
					"password"  => NICO_MAIN_PASS)
tk_doc  =REXML::Document::new(tk_rdata.body)
tk_doc.root()
ticket  =tk_doc.elements["nicovideo_user_response/ticket"].text

# Request API 2 (Nico Live)
st_rdata  =mech.post("http://live.nicovideo.jp/api/getalertstatus", "ticket" => ticket)
st_doc    =REXML::Document::new(st_rdata.body)

communities  =st_doc.elements["getalertstatus/communities"]
host_addr    =st_doc.elements["getalertstatus/ms/addr"].text
host_port    =st_doc.elements["getalertstatus/ms/port"].text.to_i
host_thread  =st_doc.elements["getalertstatus/ms/thread"].text

my_community  =communities.map(&:text)

sock       =Socket::new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
sock_addr  =Socket::sockaddr_in(host_port, host_addr)
sock.connect(sock_addr)
sock.write("<thread thread=\"#{host_thread}\" version=\"20061206\" res_from=\"-1\">\0")

puts "Start monitoring..."

# Infinite Loop
while true
	raw_data, addr  =sock.recv(1024)

	raw_data.split("\000").each do |alert_info|
		alert_info.gsub!(/<\/?[^>]*>/, "")
		alert_info  =alert_info.split(",")

		# alert_info[0]: lv ID (Consists of digit without "lv")
		# alert_info[1]: Comm ID
		# alert_info[2]: Owner ID

		if my_community.include?(alert_info[1])
			live_rdata      =mech.get("http://live.nicovideo.jp/api/getstreaminfo/lv#{alert_info[0]}")
			live_doc        =REXML::Document::new(live_rdata.body)
			live_title      =live_doc.elements["getstreaminfo/streaminfo/title"].text
			live_id         ="lv#{alert_info[0]}"
			live_comm_name  =live_doc.elements["getstreaminfo/communityinfo/name"].text
			live_comm_id    =alert_info[1]

			player_rdata  =bot.get("http://watch.live.nicovideo.jp/api/getplayerstatus?v=#{live_id}")
			player_doc    =REXML::Document::new(player_rdata.body)

			fail_count  =0
			begin
				live_owner    =player_doc.elements["getplayerstatus/stream/owner_name"].text
			rescue
				fail_count  +=1
				if fail_count <= 3
					sleep(1)
					retry
				else
					live_owner  ="<No Name>"
				end  # if
			end  # begin

			tweet  ="【生放送】#{live_owner}さんが #{live_comm_name}(http://nico.ms/#{live_comm_id}) で #{live_title}(http://nico.ms/#{live_id}) を開始しました。"

			begin
				Twitter::update(tweet)
			rescue Twitter::Error::Forbidden
			else
				puts Time::now.strftime("%Y/%m/%d %H:%M") + tweet
			end  # begin

		end  # if

	end  # each
end  # while


# [EOF]
