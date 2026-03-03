#!/bin/bash

render-prod:
    helm template umbrella-chart \
        --values umbrella-chart/values-prod.yaml

render-stag:
    helm template umbrella-chart \
        --values ./umbrella-chart/values-staging.yaml
