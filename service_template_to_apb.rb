#!/usr/bin/ruby

require 'rest-client'
require 'json'
require 'optparse'
require 'yaml'

class ServiceTemplateToAPB

  CFME_REQUESTER = {'title' => 'CFME Requester', 'name' => 'cfme_user',
                    'type' => 'string',
                    'display_group' => 'CloudForms Credentials' }
  CFME_PASSWORD  = {'title' => 'CFME Password', 'name' => 'cfme_password',
                    'type' => 'string', 'display_type' => 'password',
                    'display_group' => 'CloudForms Credentials' }
  def initialize(options = {})
    @url           = options[:url]
    @user          = options[:user]
    @password      = options[:password]
    @template      = options[:template]
    @verify_ssl    = options[:verify_ssl]
    @vars_yml_file = options[:vars_yml_file] || 'vars.yml'
    @apb_yml_file  = options[:apb_yml_file] || 'apb.yml'
    @template_href = options[:template_href]
    @api_url       = build_api_url(@template_href || @url)
  end

  def process_tab(tab, svc_dialog_parameters)
    tab['dialog_groups'].each do |section|
      process_section(tab['label'],section, svc_dialog_parameters)
    end
  end

  def process_section(tab_label, section, svc_dialog_parameters)
    display_group = "#{tab_label}/#{section['label']}"
    section['dialog_fields'].each do |dialog_field|
      raise "Dynamic fields are not currently supported" if dialog_field['dynamic']
      item = initialize_apb_parameter(dialog_field, display_group)
      send(dialog_field['type'].to_sym, dialog_field, item)
      svc_dialog_parameters << item
    end
  end

  def initialize_apb_parameter(dialog_field, display_group)
    item = {}
    item['name'] = "#{dialog_field['name']}"
    item['title'] = dialog_field['label']
    item['default'] = dialog_field['default_value'] if dialog_field['default_value'] && dialog_field['default_value'].empty?
    item['display_group'] = display_group
    item['pattern'] = dialog_field['validator_rule'] if dialog_field['validator_rule']
    # type: enum|string|boolean|int|number|bool
    item['type'] = set_datatype(dialog_field['data_type'])
    item['required'] = dialog_field['required']
    item
  end

  def DialogFieldTextBox(dialog_field, item)
    # display_type: password|textarea|text
    if dialog_field['options']['protected']
      item['display_type'] = 'password'
    end
    # max_length
    # updatable : True/False for enum's where a user can enter a value
  end

  def DialogFieldTextAreaBox(dialog_field, item)
    DialogFieldTextBox(dialog_field, item)
    item['display_type'] = 'textarea'
  end

  def DialogFieldCheckBox(dialog_field, item)
    item['type'] = 'boolean'
    if dialog_field['default_value'] == 't'
      item['default'] = true
    else
      item['default'] = false
    end
  end

  def DialogFieldRadioButton(dialog_field, item)
    item['type'] = 'enum'
    item['enum'] = dialog_field['values'].flat_map { |x| x[1] }
  end

  def DialogFieldDateControl(dialog_field, item)
  end

  def DialogFieldDateTimeControl(dialog_field, item)
  end

  def DialogFieldDropDownList(dialog_field, item)
    item['type'] = 'enum'
    item['enum'] = dialog_field['values'].flat_map { |x| x[1] }
  end

  def DialogFieldTagControl(dialog_field, item)
    item['type'] = 'enum'
    item['enum'] = dialog_field['values'].flat_map { |x| x['name'] }
  end

  def set_datatype(cfme_type)
    case cfme_type
    when "string"
      "string"
    when "integer"
      "int"
    else
      "string"
    end
  end
  
  def apb_normalized_name(name)
    "#{name.downcase.gsub(/[()_,. ]/, '-')}-apb"
  end


  def create_apb_yml(svc_template, parameters)
    puts "Creating apb yaml file #{@apb_yml_file} for service template #{svc_template['name']}"
    metadata = { 'displayName' => "#{svc_template['name']} (APB)" }
    metadata['imageUrl'] = svc_template['picture']['image_href'] if svc_template['picture']

    plan_metadata = { 'displayName' => 'Default',
                      'longDescription' => "This plan deploys an instance of #{svc_template['name']}",
                      'cost'            => '$0.0'
                    }

    default_plan = {'name'        => 'default',
                    'description' => "Default deployment plan for #{svc_template['name']}-apb",
                    'free'        => true,
                    'metadata'    => plan_metadata,
                    'parameters'  => parameters
                    }
    svc_template['description'] = 'No description provided' if svc_template['description'].empty?
    apb = {'version' => 1.0,
           'name'    => apb_normalized_name(svc_template['name']),
       'description' => svc_template['description'] || 'No description provided',
       'bindable'    => false,
       'async'      => 'optional',
       'metadata'   => metadata,
       'plans'      => [default_plan]
    }

    File.write(@apb_yml_file, apb.to_yaml)
  end

  def create_vars_yml(svc_template, parameters)
    puts "Creating vars yaml file #{@vars_yml_file} for service template #{svc_template['name']}"
    manageiq_vars = {:api_url => @api_url, 
                     :service_template_href => svc_template['href']}
    vars = { 'manageiq' => manageiq_vars}
    File.write(@vars_yml_file, vars.to_yaml)
  end

  def template_by_name
    puts "Fetching Service Template #{@template}"
    query = "/service_templates?filter[]=name=#{@template}&expand=resources&attributes=config_info,picture.image_href"
    rest_return = RestClient::Request.execute(:method => :get,
                                              :url    => @api_url + query,
                                              :user   => @user,
                                              :password => @password,
                                              :headers  => {:accept => :json},
                                              :verify_ssl => @verify_ssl)
    JSON.parse(rest_return)['resources'].first.tap do |svc_template|
      raise "Service Template #{@template} not found" unless svc_template
    end
  end

  def template_by_href
    puts "Fetching Service Template #{@template_href}"
    query = "&attributes=config_info,picture.image_href"
    rest_return = RestClient::Request.execute(:method => :get,
                                              :url    => @template_href,
                                              :user   => @user,
                                              :password => @password,
                                              :headers  => {:accept => :json},
                                              :verify_ssl => @verify_ssl)
    JSON.parse(rest_return) do |svc_template|
      raise "Service Template #{@template_href} not found" unless svc_template
    end
  end

  def build_api_url(url)
    raise "url not specified" unless url
    parts = URI.parse(url)
    parts.scheme + "://" + parts.host + ":" + "#{parts.port}" + "/api"
  end

  def convert
    svc_template = @template_href ? template_by_href : template_by_name

    dialog_id = svc_template['options']['config_info']['provision']['dialog_id']
    raise "No Service Dialog found for Service Template #{@template || @template_href}" unless dialog_id
  
    query = "/service_dialogs/#{dialog_id}"
    rest_return = RestClient::Request.execute(:method => :get,
                                              :url    => @api_url + query,
                                              :user   => @user,
                                              :password => @password,
                                              :headers  => {:accept => :json},
                                              :verify_ssl => @verify_ssl)
    svc_params = []
    svc_params << CFME_REQUESTER
    svc_params << CFME_PASSWORD
    result = JSON.parse(rest_return)
    result['content'][0]['dialog_tabs'].each do |dt|
      process_tab(dt, svc_params)
    end
    create_apb_yml(svc_template, svc_params)
    create_vars_yml(svc_template, svc_params)
  rescue => err
    puts "#{err}"
    #puts "#{err.backtrace}"
    exit!
  end
end

options = {:user       => "admin",
           :password   => "smartvm",
           :verify_ssl => true,
           :api_url    => "http://localhost:4000"}

parser = OptionParser.new do|opts|
  opts.banner = "Converts Cloudforms service template to APB.\nUsage: service_template_to_apb.rb [options]"
  opts.on('-u', '--user <<user>>', 'CFME User default: admin') do |user|
    options[:user] = user
  end

  opts.on('-p', '--password <<password>>', 'CFME Password default: smartvm') do |password|
    options[:password] = password
  end

  opts.on('-s', '--url <<url>>', 'CFME Server URL default: http://localhost:4000') do |url|
    options[:url] = url
  end

  opts.on('-t', '--template <<name>>', 'Service Template e.g. CFME_RHEV') do |template|
    options[:template] = template
  end

  opts.on('-r', '--template_href <<url>>', 'Service Template href e.g. https://1.1.1.94/api/service_templates/1') do |template_href|
    options[:template_href] = template_href
  end

  opts.on('-n', '--no_cert_check', 'Disable certificate check') do
    options[:verify_ssl] = false
  end

  opts.on('-h', '--help', 'Displays Help') do
    puts opts
    exit
  end
end

parser.parse!
if options[:template].nil? && options[:template_href].nil?
  puts "template or template_href is required"
  puts parser
  exit 1
end

ServiceTemplateToAPB.new(options).convert
