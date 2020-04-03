require 'sinatra'
require 'sinatra/reloader'
require 'json'
require 'rest_client'
require 'geocoder'


FB_ENDPOINT = "https://graph.facebook.com/v2.6/me/messages?access_token=" + "facebookトークン"

GNAVI_KEYID = "50be127ff79aecea84dbeebb31409fbb"
GNAVI_CATEGORY_LARGE_SEARCH_API = "https://api.gnavi.co.jp/master/CategoryLargeSearchAPI/v3/"
GNAVI_SEARCHAPI = "https://api.gnavi.co.jp/RestSearchAPI/v3/"

helpers do
  # ぐるなびAPIでカテゴリー一覧を取得
  def get_categories
    response = JSON.parse(RestClient.get GNAVI_CATEGORY_LARGE_SEARCH_API + "?keyid=#{GNAVI_KEYID}")
    categories = response["category_l"]
    categories
  end

  # Messengerが返せる選択肢は11個までなので11個以上は配列に含めない
  def filter_categories
    categories = []
    get_categories.each_with_index do |category, i|
      if i < 11
        hash = {
          content_type: 'text',
          title: category["category_l_name"],
          payload: category["category_l_code"], # ぐるなびAPIから取得したコードが入る
        }
        p hash
        categories.push(hash)
      else
        p "11回目は配列に入れない"
      end
    end
    categories
  end

  def set_quick_reply_of_categories sender, categories
    {
      recipient: {
        id: sender
      },
      message: {
        text: 'ありがとう :P なにが食べたいか教えて？',
        quick_replies: categories
      }
    }.to_json
  end

  def set_quick_reply_of_location sender
    {
      recipient: {
        id: sender
      },
      message: {
        text: "場所は？　:p",
      }
    }.to_json
  end

   # ぐるなびAPIでレストランを検索
   def get_restaurants lat, long, requested_category_code
    # 緯度, 経度, カテゴリー, 範囲を指定
    params = "?keyid=#{GNAVI_KEYID}&latitude=#{lat}&longitude=#{long}&category_l=#{requested_category_code}&range=3"
    restaurants = JSON.parse(RestClient.get GNAVI_SEARCHAPI + params)
    restaurants
  end

  # APIで取得したレストラン情報をMessengerで送信できる構文に整形
  def set_restaurants_info restaurants
    elements = []
    restaurants["rest"].each do |rest|
      # 三項演算子
      image = rest["image_url"]["shop_image1"].empty? ? "http://techpit-bot.herokuapp.com/images/no-image.png" : rest["image_url"]["shop_image1"]
      elements.push(
        {
          title: rest["name"],
          item_url: rest["url_mobile"],
          image_url: image,
          subtitle: "[カテゴリー: #{rest["code"]["category_name_l"][0]}] #{rest["pr"]["pr_short"]}",
          buttons: [
            {
              type: "web_url",
              url: rest["url_mobile"],
              title: "詳細を見る"
            }
          ]
        }
      )
    end
    elements
  end

  # 整形したレストラン情報をMessengerで返却できる構文に整形
  def set_reply_of_restaurant sender, elements
    {
      recipient: {
        id: sender
      },
      message: {
        attachment: {
          type: 'template',
          payload: {
            template_type: "generic",
            elements: elements
          }
        }
      }
    }.to_json
  end

end


get '/' do
  'hello world!!'
end

get '/callback' do
  if params["hub.verify_token"] != 'hogehoge'
    return 'Error, wrong validation token'
  end
  params["hub.challenge"]
end


# メッセージを受け取ったときの処理
post '/callback' do
  # メッセージ内容と送信者IDを保持
  hash = JSON.parse(request.body.read)
  message = hash["entry"][0]["messaging"][0]
  sender = message["sender"]["id"]

  # レストラン検索と打った場合にカテゴリーを返す
  if message["message"]["text"] == "お店探して"
    categories = filter_categories
    request_body = set_quick_reply_of_categories(sender, categories)
    RestClient.post FB_ENDPOINT, request_body, content_type: :json, accept: :json
  
    # quick_replyよりカテゴリーを選択した場合、受け取り住所をリクエスト
  elsif !message["message"]["quick_reply"].nil?
    # カテゴリーコードは引き回すのでグローバル変数として定義
    $requested_category_code = message["message"]["quick_reply"]["payload"]
    request_body = set_quick_reply_of_location(sender)
    RestClient.post FB_ENDPOINT, request_body, content_type: :json, accept: :json

  elsif !Geocoder.search(message["message"]["text"]).first.nil? && !$requested_category_code.nil?
    lat = Geocoder.search(message["message"]["text"]).first.coordinates[0]
    long = Geocoder.search(message["message"]["text"]).first.coordinates[1]
    restaurants = get_restaurants(lat, long, $requested_category_code)
    elements = set_restaurants_info(restaurants)
    request_body = set_reply_of_restaurant(sender, elements)
    RestClient.post FB_ENDPOINT, request_body, content_type: :json, accept: :json


  else
    text = "お見せ探してるの？。だったら「お店探して」と話しかけてね！"
    content = {
      recipient: { id: sender },
      message: { text: text }
    }
    request_body = content.to_json
    RestClient.post FB_ENDPOINT, request_body, content_type: :json, accept: :json
  end


  status 201
  body ''
end