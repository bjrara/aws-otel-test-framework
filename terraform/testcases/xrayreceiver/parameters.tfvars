# this file is defined in validator/src/main/resources/validations
validation_config = "default-xray-trace-validation.yml"

# sample application image to emit the trace data
# src: https://github.com/aws/aws-xray-sdk-go/blob/master/sample-apps/http-server/application.go
sample_app_image = "633750930120.dkr.ecr.us-west-2.amazonaws.com/amazon/aws-otel-goxray-sample-app:v1.1.0"

# data type will be emitted. Possible values: metric or trace
soaking_data_mode = "trace"

# data model type. possible values: otlp, xray, etc
soaking_data_type = "xray"