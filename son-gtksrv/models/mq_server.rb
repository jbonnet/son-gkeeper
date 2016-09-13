## SONATA - Gatekeeper
##
## Copyright (c) 2015 SONATA-NFV [, ANY ADDITIONAL AFFILIATION]
## ALL RIGHTS RESERVED.
## 
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
## 
##     http://www.apache.org/licenses/LICENSE-2.0
## 
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.
## 
## Neither the name of the SONATA-NFV [, ANY ADDITIONAL AFFILIATION]
## nor the names of its contributors may be used to endorse or promote 
## products derived from this software without specific prior written 
## permission.
## 
## This work has been performed in the framework of the SONATA project,
## funded by the European Commission under Grant number 671517 through 
## the Horizon 2020 and 5G-PPP programmes. The authors would like to 
## acknowledge the contributions of their colleagues of the SONATA 
## partner consortium (www.sonata-nfv.eu).
# encoding: utf-8
require 'bunny'
require 'pp'
require 'yaml'
require 'json' 

class MQServer
  attr_accessor :url
  
  QUEUE = 'service.instances.create'
  
  def initialize(url,logger)
    @url = url
    @logger=logger
    @channel = Bunny.new(url,:automatically_recover => false).start.create_channel
    @topic = @channel.topic("son-kernel", :auto_delete => false)
    @queue = @channel.queue(QUEUE, :auto_delete => true).bind(@topic, :routing_key => QUEUE)
    self.consume
  end

  def publish(msg, correlation_id)
    logmsg= 'MQServer.publish'
    @logger.debug(logmsg) {"msg="+msg+", correlation_id="+correlation_id}
    @topic.publish(msg, :content_type =>'text/yaml', :routing_key => QUEUE, :correlation_id => correlation_id, 
      :reply_to => @queue.name, :app_id => 'son-gkeeper')
    @logger.debug(logmsg) {"published msg '"+msg+"', with correlation_id="+correlation_id}
  end
  
  def consume
    logmsg= 'MQServer.consume'
    @logger.debug(logmsg) {" entered"}
    @queue.subscribe do |delivery_info, properties, payload|
      begin
        @logger.debug(logmsg) { "delivery_info: #{delivery_info}"}
        @logger.debug(logmsg) { "properties: #{properties}"}
        @logger.debug(logmsg) { "payload: #{payload}"}

        # We know our own messages, so just skip them
        unless properties[:app_id] == 'son-gkeeper'
          # We're interested in app_id == 'son-plugin.slm'
          parsed_payload = YAML.load(payload)
          @logger.debug(logmsg) { "parsed_payload: #{parsed_payload}"}
          status = parsed_payload['status']
          service_instance = parsed_payload['nsr']
          if service_instance && service_instance.key?('id')
            service_instance_uuid = parsed_payload['nsr']['id']
            if status
              @logger.debug(logmsg) { "status: #{status}"}
              request = Request.find_by(id: properties[:correlation_id])
              if request
                @logger.debug(logmsg) { "request['status'] #{request['status']} turned into "+status}
                request['status']=status  
                @logger.debug(logmsg) { "request['service_instance_uuid'] turned into "+service_instance_uuid}
                request['service_instance_uuid'] = service_instance_uuid
                begin
                  request.save
                  @logger.debug(logmsg) { "request saved"}
                rescue Exception => e
                  @logger.error e.message
          	      @logger.error e.backtrace.inspect
                end
              else
                @logger.error(logmsg) { "request "+properties[:correlation_id]+" not found"}
              end
            else
              @logger.error(logmsg) {'status not present'}
            end
          else
            @logger.error(logmsg) {'no service instance id present'}
          end
        end
        @logger.debug(logmsg) {" leaving..."}
      rescue Exception => e
        @logger.error e.message
  	    @logger.error e.backtrace.inspect
        @logger.debug(logmsg) {" leaving..."}
      end
    end
  end
end