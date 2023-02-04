variable "location" {
  type    = string
  default = "norwayeast"
}

resource "azurerm_resource_group" "vpn" {
  name     = "vpn-1_group"
  location = var.location
}

resource "azurerm_virtual_network" "vpn" {
  name                = "${azurerm_resource_group.vpn.name}-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.vpn.location
  resource_group_name = azurerm_resource_group.vpn.name
}

resource "azurerm_subnet" "vpn" {
  name                                           = "default"
  resource_group_name                            = azurerm_resource_group.vpn.name
  virtual_network_name                           = azurerm_virtual_network.vpn.name
  address_prefixes                               = ["10.0.0.0/24"]
  enforce_private_link_endpoint_network_policies = true
}

resource "azurerm_public_ip" "vpn" {
  name                = "vpn-1-ip"
  location            = azurerm_resource_group.vpn.location
  resource_group_name = azurerm_resource_group.vpn.name
  availability_zone   = "1"
  sku                 = "Standard"
  allocation_method   = "Static"
}

resource "azurerm_network_security_group" "vpn" {
  name                = "vpn-1-nsg"
  location            = azurerm_resource_group.vpn.location
  resource_group_name = azurerm_resource_group.vpn.name

  # SSH
  security_rule {
    name                       = "AllowSSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # HTTP to serve CA cert
  security_rule {
    name                       = "AllowHTTP"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # IKE
  security_rule {
    name                       = "AllowIKE500"
    priority                   = 102
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_range     = "500"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # IPsec NAT traversal
  security_rule {
    name                       = "AllowIPSec4500"
    priority                   = 103
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_range     = "4500"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "vpn" {
  name                = "vpn-1731_z1"
  location            = azurerm_resource_group.vpn.location
  resource_group_name = azurerm_resource_group.vpn.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.vpn.id
    public_ip_address_id          = azurerm_public_ip.vpn.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface_security_group_association" "vpn" {
  network_interface_id      = azurerm_network_interface.vpn.id
  network_security_group_id = azurerm_network_security_group.vpn.id
}

resource "azurerm_subnet_network_security_group_association" "vpn" {
  subnet_id                 = azurerm_subnet.vpn.id
  network_security_group_id = azurerm_network_security_group.vpn.id
}

resource "tls_private_key" "vpn" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "azurerm_linux_virtual_machine" "vpn" {
  name                = "vpn-1"
  location            = azurerm_resource_group.vpn.location
  resource_group_name = azurerm_resource_group.vpn.name

  size = "Standard_B1s"
  network_interface_ids = [
    azurerm_network_interface.vpn.id
  ]

  admin_ssh_key {
    public_key = tls_private_key.vpn.public_key_openssh
    username   = "torfjor"
  }

  admin_username = "torfjor"

  os_disk {
    disk_size_gb         = 30
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }

  source_image_reference {
    offer     = "0001-com-ubuntu-server-focal"
    publisher = "canonical"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }
}

output "ssh_endpoint" {
  value = azurerm_public_ip.vpn.ip_address
}

output "ssh_private_key" {
  value     = tls_private_key.vpn.private_key_openssh
  sensitive = true
}
