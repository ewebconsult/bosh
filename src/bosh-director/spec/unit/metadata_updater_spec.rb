require 'spec_helper'
require 'logger'
require 'timecop'

describe Bosh::Director::MetadataUpdater do
  subject(:metadata_updater) { described_class.new(director_metadata, logger) }
  let(:director_metadata) { {} }
  let(:instance) { BD::Models::Instance.make(deployment: deployment, vm_cid: 'fake-vm-cid', uuid: 'some_instance_id', job: 'job-value', index: 12345, availability_zone: 'az1') }
  let(:deployment) { BD::Models::Deployment.make(name: 'deployment-value') }
  let(:cloud) { Bosh::Director::Config.cloud }
  let(:cloud_factory) { instance_double(Bosh::Director::CloudFactory) }

  describe '.build' do
    it 'returns metadata updater' do
      logger = double('logger')
      allow(Bosh::Director::Config).to receive_messages(name: 'fake-director-name', logger: logger)

      updater = instance_double('Bosh::Director::MetadataUpdater')
      expect(described_class).to receive(:new).with(
          {'director' => 'fake-director-name'}, logger).and_return(updater)

      expect(described_class.build).to eq(updater)
    end
  end

  describe '#update_vm_metadata' do
    before do
      allow(Bosh::Director::CloudFactory).to receive(:new).and_return(cloud_factory)
      expect(cloud_factory).to receive(:for_availability_zone!).with(instance.availability_zone).and_return(cloud)
    end

    context 'when CPI supports setting vm metadata' do
      it 'updates vm metadata with provided metadata' do
        expected_vm_metadata = {'fake-custom-key1' => 'fake-custom-value1'}
        expect(cloud).to receive(:set_vm_metadata).with('fake-vm-cid', hash_including(expected_vm_metadata))
        metadata_updater.update_vm_metadata(instance, expected_vm_metadata)
      end

      it 'updates vm metadata with creation time' do
        Timecop.freeze do
          expected_vm_metadata = {'created_at' => Time.new.getutc.strftime('%Y-%m-%dT%H:%M:%SZ')}
          expect(cloud).to receive(:set_vm_metadata).with('fake-vm-cid', hash_including(expected_vm_metadata))
          metadata_updater.update_vm_metadata(instance, {})
        end
      end
    end

    context 'when CPI does not support setting vm metadata' do
      it 'does not mutate passed metadata' do
        passed_in_metadata = {}
        metadata_updater.update_vm_metadata(instance, passed_in_metadata)
        expect(passed_in_metadata).to eq({})
      end
    end
    
    context 'when set_vm_metadata is not part of CPI' do
      before { allow(cloud).to receive(:respond_to?).with(:set_vm_metadata).and_return(false) }

      it 'does not set vm metadata' do
        expect(cloud).not_to receive(:set_vm_metadata)
        metadata_updater.update_vm_metadata(instance, {})
      end
    end

    context 'when set_vm_metadata raises not implemented error' do
      before { allow(cloud).to receive(:set_vm_metadata).and_raise(Bosh::Clouds::NotImplemented) }

      it 'does not propagate raised error' do
        expect { metadata_updater.update_vm_metadata(instance, {}) }.to_not raise_error
      end
    end
  end

  describe '#deployment_metadata' do
    let(:director_metadata) { {'fake-director-key1' => 'fake-director-value1'} }

    it 'adds director metadata' do
      metadata = metadata_updater.deployment_metadata(instance, {})

      expect(metadata).to include({'fake-director-key1' => 'fake-director-value1'})
    end

    it 'adds deployment specific metadata' do
      metadata = metadata_updater.deployment_metadata(instance, {})

      expect(metadata).to include({'deployment' => 'deployment-value'})
    end

    it 'adds instance specific metadata' do
      expected_vm_metadata = {
        'id' => 'some_instance_id',
        'job' => 'job-value',
        'index' => '12345',
        'name' => 'job-value/some_instance_id',
      }

      metadata = metadata_updater.deployment_metadata(instance, {})

      expect(metadata).to include(expected_vm_metadata)
    end

    it 'turns job index metadata into a string' do
      metadata = metadata_updater.deployment_metadata(instance, {})

      expect(metadata).to include({'index' => '12345'})
    end
  end
end
