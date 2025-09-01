Vagrant.configure("2") do |config|
#check cache 
  config.cache.auto_detect = true
  

  etcHosts = ""  # permet de definir  le contenu de etchost, dns des machines
  rabbitmq = ""  # poser une question à l'user pour soit lancer des machines vierges ou avec rabbitmq

 
  case ARGV[0]
    when "provision", "up"
    print "Souhaitez vous installer rabbitmq cluster (yes/no) ?\n"
    rabbitmq = STDIN.gets.chomp
    print "\n"
  end

  # some settings for common server (not for haproxy) # installation des elements utilses et du ssh pour accepter la connexion
  common = <<-SHELL
  sudo apt update -q 2>&1 >/dev/null
  sudo apt install -y -q wget curl gnupg apt-transport-https unzip dnsutils nfs-common python3  2>&1 >/dev/null
  sed -i 's/ChallengeResponseAuthentication no/ChallengeResponseAuthentication yes/g' /etc/ssh/sshd_config
  sudo systemctl restart sshd
  SHELL

  # Definition de notre box  vagrant init debian/bookworm64 --box-version 12.20250126.1
  config.vm.box = "debian/bookworm64"
  config.vm.box_url = "https://app.vagrantup.com/debian/boxes/bookworm64"
  config.vm.box_version = "12.20250126.1"

  # Definition des machines (un leader et deux followers principe du RAFL (n/2 +1 ou 2n+1)
  NODES = [
  { :hostname => "rabbit-node1", :ip => "192.168.59.40", :cpus => 1, :mem => 698, :type => "rmq_leader" },
  { :hostname => "rabbit-node2", :ip => "192.168.59.41", :cpus => 1, :mem => 698, :type => "rmq_follower" },
  { :hostname => "rabbit-node3", :ip => "192.168.59.42", :cpus => 1, :mem => 698, :type => "rmq_follower" }
  #{ :hostname => "elk",          :ip => "192.168.59.43", :cpus => 4, :mem => 4048, :type => "elk" }
  ]

  # creation de nos fichiers hosts
  
  NODES.each do |node|
    etcHosts += "echo '" + node[:ip] + "   " + node[:hostname] + "'>> /etc/hosts" + "\n"
  end #end NODES
 
  NODES.each do |node|
    config.vm.define node[:hostname] do |cfg|
      cfg.vm.hostname = node[:hostname]
      cfg.vm.network "private_network", ip: node[:ip]
      cfg.vm.network "forwarded_port", guest: 8404, host: 8404, auto_correct: true
      cfg.vm.provider "virtualbox" do |v|
	v.customize [ "modifyvm", :id, "--cpus", node[:cpus] ]
        v.customize [ "modifyvm", :id, "--memory", node[:mem] ]
        v.customize [ "modifyvm", :id, "--natdnshostresolver1", "on" ]
        v.customize [ "modifyvm", :id, "--natdnsproxy1", "on" ]
        v.customize [ "modifyvm", :id, "--name", node[:hostname] ]
	v.customize [ "modifyvm", :id, "--ioapic", "on" ]
        v.customize [ "modifyvm", :id, "--nictype1", "virtio" ]
      end 
      
      cfg.vm.provision :shell, :inline => etcHosts
      cfg.vm.provision :shell, :inline => common
      
      # if node[:hostname] == "elk"
      #     cfg.vm.provision :shell, :path => "provision_elk.sh"
      # end

      if rabbitmq == "yes"
        if node[:type] == "rmq_leader"
          cfg.vm.provision :shell, :path => "provision.sh", :args => "leader"
          #cfg.vm.provision :shell, :path => "provision/common.sh"
	      end

        if node[:type] == "rmq_follower"
          cfg.vm.provision :shell, :path => "provision.sh", :args => "follower"
          #cfg.vm.provision :shell, :path => "provision/common.sh"
      	end
      end
    end 
  end 

end 
