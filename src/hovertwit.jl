#!/usr/bin/env julia

using Twitter, DataFrames, TimeZones, Dates

# TODO: make calling this easier
twitterauth(ENV['API_KEY'],
    ENV['API_SECRET'],
    ENV['ACCESS_TOKEN'],
    ENV['ACCESS_TOKEN_SECRET'],
)

# TODO: get tweets around a certain date / time
# sometimes this doesn't seem to work and just hangs for ages
# just run it interactively instead
tweets = get_user_timeline(screen_name = "hovertravelltd", count = 1000)

const twitter_time_format = Dates.DateFormat("e u dd HH:MM:SS zzzzz yyyy")
time2time(t) = ZonedDateTime(t,twitter_time_format)

tidy = DataFrame(time = getfield.(tweets, :created_at) .|> time2time, tweet = getfield.(tweets,:text))

tidy[contains.(tidy[:tweet],r"services"i),:]

# Sketch:
# - Hovercraft is assumed to be running
# - Once a tweet emerges saying it is cancelled, Hovercraft is cancelled until the next day _or_ until a tweet saying resume (with a time) or 'services operating on time'
#   - if we can't parse the resume time, assume it is tweet time

function resumetweet2time(row)
    now = row.time
    date = TimeZones.yearmonthday(now)
    tz = TimeZones.timezone(now)
    # catch error below?
    time = parse.(Int, match(r"([0-9]{2})[:.]([0-9]{2})", row.tweet).captures)
    ZonedDateTime(date..., time..., tz)
end

cancellations = []
cancelled = false
canceltime = ZonedDateTime(0,TimeZone("UTC"))
resumetime = ZonedDateTime(0,TimeZone("UTC"))
for tweet in reverse(eachrow(tidy))
    if cancelled && (TimeZones.yearmonthday(tweet.time) != TimeZones.yearmonthday(canceltime))
        date = TimeZones.yearmonthday(canceltime)
        tz = TimeZones.timezone(canceltime)
        ZonedDateTime(date..., 23, 59, tz)
        cancelled = false
        push!(cancellations, (canceltime, resumetime))
    end
    if contains(tweet.tweet , r"cancel"i) && !cancelled
        cancelled = true
        canceltime = tweet.time
    end
    if contains(tweet.tweet , r"resume"i) && cancelled
        cancelled = false
        resumetime = resumetweet2time(tweet)
        push!(cancellations, (canceltime, resumetime))
    end
end
cancellations
