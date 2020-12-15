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
#
# tweets = get_user_timeline(screen_name = "hovertravelltd", count = 1000)
#
# hmm, looks like 10k tweets maxes out at 3200 tweets - Hovertravel has 11.6k apparently. Maybe we're limited to more recent ones?
#

const twitter_time_format = Dates.DateFormat("e u dd HH:MM:SS zzzzz yyyy")
time2time(t) = ZonedDateTime(t,twitter_time_format)
import JLD2
# JLD2.@save "hovercraft.jld2" tidy
JLD2.@load "hovercraft.jld2" tidy

# tidy = DataFrame(time = getfield.(tweets, :created_at) .|> time2time, tweet = getfield.(tweets,:text))


# tidy[contains.(tidy[:tweet],r"services"i),:]

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

cancellations = DataFrame(cancelled = [], resumed = [])
cancelled = false
canceltime = ZonedDateTime(0,TimeZone("UTC"))
resumetime = ZonedDateTime(0,TimeZone("UTC"))
for tweet in reverse(eachrow(tidy))
    if cancelled && (TimeZones.yearmonthday(tweet.time) != TimeZones.yearmonthday(canceltime))
        date = TimeZones.yearmonthday(canceltime)
        tz = TimeZones.timezone(canceltime)
        resumetime = ZonedDateTime(date..., 23, 59, tz)
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
cancellations.date = TimeZones.yearmonth.(cancellations.cancelled)

# Most / least unreliable months
g = groupby(cancellations,:date)
[(g[i].date[1], size(g[i])) for i in 1:length(g)] # for some reason default iteration over g is weird

timeseries = []
times = []
for row in eachrow(cancellations)
    push!(times,row.cancelled)
    push!(times,row.resumed)
    push!(timeseries,1)
    push!(timeseries,0)
end

using Plots
plot(times .|> DateTime,timeseries; legend=:none,seriestype=:step, fill=(0,1,:lightblue))

# Was the hovercraft running at ZonedDateTime t?
# Might need to improve performance of this if we want to look it up at
# 30 minute resolutions for historical data over the course of a year
#
# Since the rows are sorted, we could first find the last cancelled before our time
# and give up if it resumes before our time.
function hoverrun(t)
    !any(r -> r.cancelled < t < r.resumed, eachrow(cancellations))
end


# So how do we go about predicting this stuff?
# I think a random forest is probably the best first thing to try - weatherdata(t) to predict hoverrun(t)
# but it might be wise to also look at weatherdata(t+-/(some time)) to predict hoverrun(t) - i.e. with a sliding window

dates = ZonedDateTime(2019,07,TimeZone("UTC")):Dates.Hour(1):ZonedDateTime(2020,12,TimeZone("UTC"))
steps = dates |> length
dummy = DataFrame(dates = dates, winddir = rand((:N,:NE,:E,:SE,:S,:SW,:W,:NW),steps), windspeed = rand(15:30,steps) .- hoverrun.(dates).*10, waveheight = rand(1:0.1:2.5, steps) .- hoverrun.(dates), hover = hoverrun.(dates))

# Now we have dummy data, we just need to predict
#
# This looks pretty straightforward:
# https://github.com/bensadeghi/DecisionTree.jl


# For getting real historic data,
# https://dev.meteostat.net/ looks like it might be OK, but it probably doesn't include wave height
# Once I have a proof of concept I may have to send a friendly email to the magicseaweed people
#
using DecisionTree
labels = dummy.hover
features = [dummy.waveheight  dummy.windspeed  dummy.winddir]
model = DecisionTreeClassifier(max_depth=4)
fit!(model,features,labels)
predict_proba(model, [1.4, 10.0, :S])


using CSV
# NB need to add headers manually to CSV
catherine = CSV.read("data/wight_catherine_point_03866.csv";copycols=true)
# need also to skipmissing?
onlyvalid = filter(r->(r.date >= Date("2019-03-31")) && (7 <= r.hour <= 23) ,catherine)
# catherine = CSV.read("data/southampton_03865.csv";copycols=true)
onlyvalid.zd = ZonedDateTime.(Dates.DateTime.(onlyvalid.date) .+ Dates.Hour.(onlyvalid.hour), TimeZone("UTC"))
onlyvalid.hover = hoverrun.(onlyvalid.zd)

# Need to only check for hovercraft running when we have data for it
# First day we have is 2019-03-31
# Let's also restrict ourselves to 7/8AM to 10/11PM

features = [sin.(deg2rad.(onlyvalid.winddir_deg)) onlyvalid.windspeed]
labels = onlyvalid.hover
model = DecisionTreeClassifier(max_depth=4)
fit!(model,features,labels)
predict_proba(model, [0.3, 50.4])

# IRL there doesn't seem to be much relationship between windspeed at catherine
# and whether hovercraft runs
#
# nor with southampton
#
# maybe we just can't do this after all? 
#
# But there definitely is a link with wave height. Just need to get that forecast.
#
#  using Plots
#  
#  scatter(onlyvalid.windspeed, onlyvalid.hover)
#  scatter(dummy.windspeed, dummy.hover)

