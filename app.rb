require 'sinatra'
require 'socket'

set :port, 4567
set :bind, '0.0.0.0'
set :views, File.join(__dir__, 'views')
set :public_folder, File.join(__dir__, 'public')
set :erb, escape_html: false
enable :sessions

LOOPBACK_ADDRS = %w[127.0.0.1 ::1 ::ffff:127.0.0.1].freeze

helpers do
  def dm_host?
    LOOPBACK_ADDRS.include?(request.ip)
  end

  def viewing_as_player?
    dm_host? && session[:view_as_player]
  end

  def dm_view?
    dm_host? && !session[:view_as_player]
  end

  def server_address
    Socket.ip_address_list
          .find { |a| a.ipv4? && !a.ipv4_loopback? }
          &.ip_address || '127.0.0.1'
  end

  def menu_items
    [
      { label: 'Home',             href: '/',                 dm_only: false },
      { label: 'Character Sheets', href: '/character-sheets', dm_only: false },
      { label: 'Scene',            href: '/scene',            dm_only: false },
      { label: 'Store',            href: '/store',            dm_only: false },
      { label: 'Notes',            href: '/notes',            dm_only: false },
      { label: 'Social',           href: '/social',           dm_only: false },
      { label: 'Status',           href: '/status',           dm_only: true  }
    ]
  end
end

get '/' do
  redirect '/character-sheets'
end

get '/character-sheets' do
  erb :character_sheets
end

get '/scene' do
  erb :scene
end

get '/store' do
  erb :store
end

get '/notes' do
  erb :notes
end

get '/social' do
  erb :social
end

get '/status' do
  redirect '/character-sheets' unless dm_view?
  @view = %w[status dice check].include?(params[:view]) ? params[:view] : 'status'
  @check = dummy_check
  @rolls = dummy_rolls
  erb :status
end

post '/view-as/toggle' do
  halt 403 unless dm_host?
  session[:view_as_player] = !session[:view_as_player]
  redirect(request.referer || '/')
end

def dummy_rolls
  [
    {
      creature_name: 'Orc Patrol',
      roll_name: 'Attack (Greataxe)',
      dice_count: 3, tn: 5, starting_value: 0,
      reroll: nil,
      nudge:  nil,
      initial_dice: [2, 5, 6],
      post_reroll_dice: nil,
      post_nudge_dice: nil,
      dois: 2, critical_count: 1, die_size: 10
    },
    {
      creature_name: 'Bryn Ironvein',
      roll_name: 'Attack (Longsword)',
      dice_count: 8, tn: 1, starting_value: 0,
      reroll: { amount: 2, max: false, sign: :neg, label: 'Unsettling Words' },
      nudge:  nil,
      initial_dice: [8, 6, 10, 1, 10, 4, 8, 10],
      post_reroll_dice: [nil, nil, nil, nil, 9, nil, nil, 1],
      post_nudge_dice: nil,
      dois: 9, critical_count: 1, die_size: 10
    },
    {
      creature_name: 'Wisp Familiar',
      roll_name: 'Aid (Guidance)',
      dice_count: 4, tn: 5, starting_value: 1,
      reroll: { amount: 1, max: false, sign: :pos, label: 'Bardic Inspiration' },
      nudge:  { amount: 1, max: false, sign: :pos, label: 'Guidance' },
      initial_dice: [1, 3, 5, 8],
      post_reroll_dice: [1, 5, 5, 8],
      post_nudge_dice: [1, 5, 6, 9],
      dois: 4, critical_count: 0, die_size: 8
    },
    {
      creature_name: 'Cleric of Ruin',
      roll_name: 'Smite (Curse of Doubt)',
      dice_count: 6, tn: 4, starting_value: 0,
      reroll: { amount: 0, max: true, sign: :neg, label: 'Curse of Doubt' },
      nudge:  nil,
      initial_dice: [5, 8, 2, 6, 9, 3],
      post_reroll_dice: [3, 7, nil, 2, 4, nil],
      post_nudge_dice: nil,
      dois: 1, critical_count: 0, die_size: 10
    },
    {
      creature_name: 'Frenzied Berserker',
      roll_name: 'Attack (Reckless)',
      dice_count: 10, tn: 5, starting_value: -1,
      reroll: { amount: 0, max: true, sign: :pos, label: 'Reckless' },
      nudge:  nil,
      initial_dice: [1, 2, 4, 5, 7, 3, 6, 1, 8, 4],
      post_reroll_dice: [nil, nil, nil, 5, 7, nil, 6, nil, 8, nil],
      post_nudge_dice: nil,
      dois: 4, critical_count: 0, die_size: 10
    }
  ]
end

def dummy_check
  {
    supporting: [
      {
        creature_name: 'Bryn Ironvein',
        roll_name: 'Attack (Longsword)',
        dice_count: 8, tn: 2, starting_value: 0,
        reroll: { amount: 2, max: false, sign: :neg, label: 'Unsettling Words' },
        nudge: nil,
        initial_dice: [10, 8, 7, 4, 8, 4, 6, 9],
        post_reroll_dice: [7, nil, nil, nil, nil, nil, nil, 10],
        post_nudge_dice: nil,
        dois: 9, critical_count: 1, die_size: 10
      },
      {
        creature_name: 'Shield of Faith',
        roll_name: 'Aid',
        dice_count: 5, tn: 6, starting_value: 0,
        reroll: { amount: 1, max: false, sign: :neg, label: 'Unsettling Words' },
        nudge: nil,
        initial_dice: [4, 5, 3, 8, 1],
        post_reroll_dice: [nil, nil, nil, 3, nil],
        post_nudge_dice: nil,
        dois: -1, critical_count: 0, die_size: 10
      }
    ],
    opposing: [
      {
        creature_name: 'Bandit Captain',
        roll_name: 'Dodge',
        dice_count: 6, tn: 6, starting_value: 0,
        reroll: { amount: 3, max: false, sign: :pos, label: 'Bardic Inspiration' },
        nudge: nil,
        initial_dice: [5, 9, 8, 1, 10, 6],
        post_reroll_dice: [nil, nil, nil, 9, nil, nil],
        post_nudge_dice: nil,
        dois: 6, critical_count: 1, die_size: 10
      }
    ]
  }
end
