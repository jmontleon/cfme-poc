CFME-POC
--------

About:
======
This repo contains scripts and artifacts to help with a cfme registry adapter PoC running against the [ManageIQ (APB)](https://github.com/ansibleplaybookbundle/manageiq-apb) in Openshift.

Testing:
========
1. Setup openshift origin with the automation broker. One option is [catasb](https://github.com/fusor/catasb).
1. Once openshift and the Broker are running launch the ManageIQ APB. Take care to carry out the instructions in the description. The APB will take about 5 minutes to run. The app container will take about an additional 5 minutes to create the remaining deployment configs.
1.  `oc edit configmap -n ansible-service-broker broker-config`
    Add a registry, i.e:
    ```
          - type: "cfme"
            name: "miq"
            url: "https://manageiq-miq.172.17.0.1.nip.io"
            org: "ansibleplaybookbundle"
            user: "admin"
            pass: "smartvm"
            white_list:
              - ".*$"
    ```
1. Edit the vars in `setup.yml` to match your Openshift and MIQ instances. Then run `ansible-playbook setup.yml` to configure your Openshift instance as a Cloud Provider and create a service dialog and service template. You should also see a `Test (APB)` in the Openshift UI after the Service Catalog relists.
1. It should then be possible to run the included ruby script, for example: `./service_template_to_apb.rb -u admin -p smartvm -s https://manageiq-miq1.172.17.0.1.nip.io -n -r https://manageiq-miq1.172.17.0.1.nip.io/api/service_templates/1000000000001`

Workarounds:
============
Dockerfile.manageiq-ui-worker, service_templates_controller.rb, and container_manager.rb were used to create docker.io/jmontleon/manageiq-ui-worker:latest from docker.io/manageiq/manageiq-ui-worker:latest. This image fixes a couple API bugs in order to enable using the included ansible playbook to set up objects for a test environment. When the setup.yml playbook is run it will patch the UI deployment and retry adding the container provider until the new pod is up, which will allow it to work.

Associated Issues:
* [ManageIQ Openshift Provider #93](https://github.com/ManageIQ/manageiq-providers-openshift/issues/93)
* [ManageIQ #17211](https://github.com/ManageIQ/manageiq/issues/17211)

Todo:
=====
* Improve CFME Registry Adapter in the Automation Broker [PoC PR](https://github.com/openshift/ansible-service-broker/pull/864) / [bundle-lib](https://github.com/automationbroker/bundle-lib)
* Automate patching configmap in setup.yml
* Create a CFME Runner APB capable of processing parameters and generating a request.
