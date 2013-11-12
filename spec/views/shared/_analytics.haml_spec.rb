require 'spec_helper'

describe 'shared/_analytics.haml' do
  fixtures :affiliates
  let(:affiliate) { affiliates(:basic_affiliate) }

  context 'when DAP is enabled for affiliate' do
    before do
      affiliate.dap_enabled = true
      assign :affiliate, affiliate
    end

    it 'should render federated Google Analytics code' do
      render
      rendered.should contain('//www.usa.gov/resources/js/federated-analytics.js')
    end
  end

  context 'when DAP is disabled for affiliate' do
    before do
      affiliate.dap_enabled = false
      assign :affiliate, affiliate
    end

    it 'should not render federated Google Analytics code' do
      render
      rendered.should_not contain('//www.usa.gov/resources/js/federated-analytics.js')
    end
  end
end