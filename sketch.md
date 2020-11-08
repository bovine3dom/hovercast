Aim: predict whether Hovercraft will run based on marine weather forecast. Give indication of certainty of prediction.

Method: train random forest from historical weather data and historical data on whether hovercraft ran.

Eventual domain: hovercast.blanthorn.com

Subgoals:

1. find random forest / crossfold validation library for Julia
    - predict first of all from dummy data (e.g. if wave height > 1.5m don't run)
2. scrape historical hovercraft data from twitter
    - find library that does this
3. find marine forecast / historical data API
    - magicseaweed.com looks decent: https://magicseaweed.com/developer/api - but access is via email only, so probably the last step
    - get this into julia
