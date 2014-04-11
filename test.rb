require 'aws-sdk-core'
require 'yaml'


config = YAML.load_file('config.yml')

Aws.config = {
    access_key_id: config['access_key_id'],
    secret_access_key: config['secret_access_key'],
    region: config['region']
}

cw = Aws::CloudWatch.new

instance_id = 'i-e5281aa4'
time = Time.new
time.gmtime

result = cw.get_metric_statistics(
    namespace: 'AWS/EC2',
    metric_name: 'CPUUtilization',
    statistics: ['Average'],
    start_time: time-1000,
    end_time: time+1000,
    period: 60,
    dimensions: [{name: 'InstanceId', value: "#{instance_id}"}]
)

puts YAML::dump(result)
