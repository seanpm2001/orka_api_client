# frozen_string_literal: true

require_relative "attr_predicate"
require_relative "protocol_port_mapping"
require_relative "disk"

module OrkaAPI
  module Models
    # A virtual machine deployed on a {Node node} from an existing {VMConfiguration VM configuration} or cloned from
    # an existing virtual machine. In the case of macOS VMs, this is a full macOS VM inside of a
    # {https://www.docker.com/resources/what-container Docker container}.
    class VMInstance
      extend AttrPredicate

      # @return [String] The ID of the VM.
      attr_reader :id

      # @return [String] The name of the VM.
      attr_reader :name

      # @return [Node] The node the VM is deployed on.
      attr_reader :node

      # @return [User] The owner of the VM, i.e. the user which deployed it.
      attr_reader :owner

      # @return [String] The state of the node the VM is deployed on.
      attr_reader :node_status

      # @return [String] The IP of the VM.
      attr_reader :ip

      # @return [Integer] The port used to connect to the VM via VNC.
      attr_reader :vnc_port

      # @return [Integer] The port used to connect to the VM via macOS Screen Sharing.
      attr_reader :screen_sharing_port

      # @return [Integer] The port used to connect to the VM via SSH.
      attr_reader :ssh_port

      # @return [Integer] The number of CPU cores allocated to the VM.
      attr_reader :cpu

      # @return [Integer] The number of vCPUs allocated to the VM.
      attr_reader :vcpu

      # @return [String] The amount of RAM allocated to the VM.
      attr_reader :ram

      # @return [Image] The base image the VM was deployed from.
      attr_reader :base_image

      # @return [VMConfiguration] The VM configuration object this instance is based on.
      attr_reader :config

      # @return [String]
      attr_reader :configuration_template

      # @return [String] The status of the VM, at the time this class was initialized.
      attr_reader :status

      # @return [Boolean] True if IO boost is enabled for this VM.
      attr_predicate :io_boost

      # @return [Boolean] True if this VM is using a prior saved state rather than a clean base image.
      attr_predicate :use_saved_state

      # @return [Array<ProtocolPortMapping>] The port mappings established for this VM.
      attr_reader :reserved_ports

      # @return [DateTime] The time when this VM was deployed.
      attr_reader :creation_time

      # @api private
      # @param [Hash] hash
      # @param [Connection] conn
      # @param [Boolean] admin
      def initialize(hash, conn:, admin: false)
        @conn = conn
        @admin = admin
        deserialize(hash)
      end

      # @!macro [new] vm_instance_state_note
      #   @note Calling this will not change the state of this object, and thus not change the return values of
      #     attributes like {#status}. You must fetch a new object instance from the client to refresh this data.

      # Remove the VM instance.
      #
      # If the VM instance belongs to the user associated with the client's token then the client only needs to be
      # configured with a token. Otherwise, if you are removing a VM instance associated with another user, you need
      # to configure the client with both a token and a license key.
      #
      # @macro vm_instance_state_note
      #
      # @return [void]
      def delete
        @conn.delete("resources/vm/delete") do |r|
          r.body = {
            orka_vm_name: @id,
          }.compact

          auth_type = [:token]
          auth_type << :license if @admin
          r.options.context = {
            orka_auth_type: auth_type,
          }
        end
      end

      # Power ON the VM.
      #
      # @macro auth_token
      #
      # @macro vm_instance_state_note
      #
      # @return [void]
      def start
        body = {
          orka_vm_name: @id,
        }.compact
        @conn.post("resources/vm/exec/start", body) do |r|
          r.options.context = {
            orka_auth_type: :token,
          }
        end
      end

      # Power OFF the VM.
      #
      # @macro auth_token
      #
      # @macro vm_instance_state_note
      #
      # @return [void]
      def stop
        body = {
          orka_vm_name: @id,
        }.compact
        @conn.post("resources/vm/exec/stop", body) do |r|
          r.options.context = {
            orka_auth_type: :token,
          }
        end
      end

      # Suspend the VM.
      #
      # @macro auth_token
      #
      # @macro vm_instance_state_note
      #
      # @return [void]
      def suspend
        body = {
          orka_vm_name: @id,
        }.compact
        @conn.post("resources/vm/exec/suspend", body) do |r|
          r.options.context = {
            orka_auth_type: :token,
          }
        end
      end

      # Resume the VM. The VM must already be suspended.
      #
      # @macro auth_token
      #
      # @macro vm_instance_state_note
      #
      # @return [void]
      def resume
        body = {
          orka_vm_name: @id,
        }.compact
        @conn.post("resources/vm/exec/resume", body) do |r|
          r.options.context = {
            orka_auth_type: :token,
          }
        end
      end

      # Revert the VM to the latest state of its base image. This operation restarts the VM.
      #
      # @macro auth_token
      #
      # @macro vm_instance_state_note
      #
      # @return [void]
      def revert
        body = {
          orka_vm_name: @id,
        }.compact
        @conn.post("resources/vm/exec/revert", body) do |r|
          r.options.context = {
            orka_auth_type: :token,
          }
        end
      end

      # List the disks attached to the VM. The VM must be non-scaled.
      #
      # @macro auth_token
      #
      # @macro lazy_enumerator
      #
      # @return [Enumerator<Disk>] The enumerator of the disk list.
      def disks
        Enumerator.new do
          drives = @conn.get("resources/vm/list-disks") do |r|
            r.options.context = {
              orka_auth_type: :token,
            }
          end.body["drives"]
          drives.map do |hash|
            Disk.new(
              type:   hash["type"],
              device: hash["device"],
              target: hash["target"],
              source: hash["source"],
            )
          end
        end
      end

      # Attach a disk to the VM. The VM must be non-scaled.
      #
      # You can attach any of the following disks:
      #
      # * Any disks created with {Client#generate_empty_image}
      # * Any non-bootable images available in your Orka storage and listed by {Client#images}
      #
      # @macro auth_token
      #
      # @note Before you can use the attached disk, you need to restart the VM with a {#stop manual stop} of the VM,
      #   followed by a {#start manual start} VM. A software reboot from the OS will not trigger macOS to recognize
      #   the disk.
      #
      # @param [Image, String] image The disk to attach to the VM.
      # @param [String] mount_point The mount point to attach the VM to.
      # @return [void]
      def attach_disk(image:, mount_point:)
        body = {
          orka_vm_name: @id,
          image_name:   image.is_a?(Image) ? image.name : image,
          mount_point:  mount_point,
        }.compact
        @conn.post("resources/vm/attach-disk", body) do |r|
          r.options.context = {
            orka_auth_type: :token,
          }
        end
      end

      # Scale the VM to the specified number of replicas.
      #
      # When you are working with scaled VMs, the following limitations are in place:
      #
      # * Some operations are not available for scaled VMs (saving an image, committing changes to a base image,
      #   cloning a VM, migrating a VM).
      # * If you specify a node during deployment, scaling is limited to the resources of that node and will not
      #   create new replicas on other nodes.
      # * All replicas share the same ID.
      # * When you scale down, you have no control over which replicas will be destroyed and which ones will be
      #   preserved. This might result in loss of data.
      # * When you scale up, newly deployed replicas use the base image of the original VM config. Changes from any
      #   other running replicas are not applied to the new replicas.
      # * Deleting a VM deletes all replicas.
      #
      # @macro auth_token
      #
      # @param [Integer] replicas The number of replicas to scale to.
      # @return [void]
      def scale(replicas)
        body = {
          orka_vm_name: @id,
          replicas:     replicas,
        }.compact
        @conn.patch("resources/vm/scale", body) do |r|
          r.options.context = {
            orka_auth_type: :token,
          }
        end
      end

      # Un-scale a scaled VM. This removes any additional replicas of the VM and leaves only one running copy.
      #
      # When you scale down, you have no control over which replicas will be destroyed and which one will be
      # preserved. This might result in loss of data.
      #
      # @macro auth_token
      #
      # @return [void]
      def unscale
        scale(1)
      end

      # Migrate the VM from its {#node current node} to another destination node. The destination node should be
      # different from the source node.
      #
      # This operation changes the IP of the migrated VM and might change its assigned ports. This operation removes
      # the VM from the source node.
      #
      # @macro auth_token
      #
      # @macro vm_instance_state_note
      #
      # @param [Node, String] destination_node The node to migrate the VM to.
      # @return [void]
      def migrate(destination_node)
        body = {
          orka_vm_name:      @id,
          current_node_name: @node.name,
          new_nodes:         [destination_node.is_a?(Node) ? node.name : node],
        }.compact
        @conn.post("resources/vm/migrate", body) do |r|
          r.options.context = {
            orka_auth_type: :token,
          }
        end
      end

      # Clone the VM from its {#node current node} to another destination node. The destination node should be
      # different from the source node.
      #
      # This operation retains the VM on the source node. The clone receives a new ID and might receive a new IP and
      # assigned ports, based on the destination node.
      #
      # @macro auth_token
      #
      # @param [Node, String] destination_node The node to migrate the VM to.
      # @return [void]
      def clone(destination_node)
        body = {
          orka_vm_name:      @id,
          current_node_name: @node.name,
          new_nodes:         [destination_node.is_a?(Node) ? node.name : node],
        }.compact
        @conn.post("resources/vm/clone", body) do |r|
          r.options.context = {
            orka_auth_type: :token,
          }
        end
      end

      # Save the VM configuration state (disk and memory).
      #
      # If VM state is previously saved, it is overwritten. To overwrite the VM state, it must not be used by any
      # deployed VM.
      #
      # @macro auth_token
      #
      # @note Saving VM state is restricted only to VMs that have GPU passthrough disabled.
      #
      # @return [void]
      def save_state
        body = {
          orka_vm_name: @id,
        }.compact
        @conn.post("resources/vm/configs/save-state", body) do |r|
          r.options.context = {
            orka_auth_type: :token,
          }
        end
      end

      # Apply the current state of the VM's image to the original base image in the Orka storage. Use this operation
      # to modify an existing base image. All VM configs that reference this base image will be affected.
      #
      # The VM must be non-scaled. The base image to which you want to commit changes must be in use by only one VM.
      # The base image to which you want to commit changes must not be in use by a VM configuration with saved VM
      # state.
      #
      # @macro auth_token
      #
      # @return [void]
      def commit_to_base_image
        body = {
          orka_vm_name: @id,
        }.compact
        @conn.post("resources/image/commit", body) do |r|
          r.options.context = {
            orka_auth_type: :token,
          }
        end
      end

      # Save the current state of the VM's image to a new base image in the Orka storage. Use this operation to
      # create a new base image.
      #
      # The VM must be non-scaled. The base image name that you specify must not be in use.
      #
      # @macro auth_token
      #
      # @param [String] image_name The name to give to the new base image.
      # @return [Image] The lazily-loaded new base image.
      def save_new_base_image(image_name)
        body = {
          orka_vm_name: @id,
          new_name:     image_name,
        }.compact
        @conn.post("resources/image/save", body) do |r|
          r.options.context = {
            orka_auth_type: :token,
          }
        end
        Image.lazy_prepare(image_name, conn: @conn)
      end

      # Resize the current disk of the VM and save it as a new base image. This does not affect the original base
      # image of the VM.
      #
      # @macro auth_token
      #
      # @param [String] username The username of the VM user.
      # @param [String] password The password of the VM user.
      # @param [String] image_name The new name for the resized image.
      # @param [String] image_size The size of the new image (in k, M, G, or T), for example +"100G"+.
      # @return [Image] The lazily-loaded new base image.
      def resize_image(username:, password:, image_name:, image_size:)
        body = {
          orka_vm_name:   @id,
          vm_username:    username,
          vm_password:    password,
          new_image_size: image_size,
          new_image_name: image_name,
        }.compact
        @conn.post("resources/image/resize", body) do |r|
          r.options.context = {
            orka_auth_type: :token,
          }
        end
        Image.lazy_prepare(image_name, conn: @conn)
      end

      private

      def deserialize(hash)
        @owner = User.lazy_prepare(email: hash["owner"], conn: @conn)
        @name = hash["virtual_machine_name"]
        @id = hash["virtual_machine_id"]
        @node = Node.lazy_prepare(name: hash["node_location"], conn: @conn, admin: @admin)
        @node_status = hash["node_status"]
        @ip = hash["virtual_machine_ip"]
        @vnc_port = hash["vnc_port"].to_i
        @screen_sharing_port = hash["screen_sharing_port"].to_i
        @ssh_port = hash["ssh_port"].to_i
        @cpu = hash["cpu"]
        @vcpu = hash["vcpu"]
        @ram = hash["RAM"]
        @base_image = Image.lazy_prepare(name: hash["base_image"], conn: @conn)
        @config = VMConfiguration.lazy_prepare(name: hash["image"], conn: @conn)
        @configuration_template = hash["configuration_template"]
        @status = hash["vm_status"]
        @io_boost = hash["io_boost"]
        @use_saved_state = hash["use_saved_state"]
        @reserved_ports = hash["reserved_ports"].map do |mapping|
          ProtocolPortMapping.new(
            host_port:  mapping["host_port"],
            guest_port: mapping["guest_port"],
            protocol:   mapping["protocol"],
          )
        end
        @creation_time = DateTime.iso8601(hash["creation_timestamp"])
      end
    end
  end
end
