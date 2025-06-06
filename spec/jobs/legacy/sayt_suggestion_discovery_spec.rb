# frozen_string_literal: true

require 'spec_helper'

describe SaytSuggestionDiscovery, '#perform(affiliate_name, affiliate_id, date_int, limit)' do
  let(:affiliate) { affiliates(:power_affiliate) }
  let(:date_int) { 20_140_626 }
  let(:top_n_exists_args) do
    [
      affiliate.name,
      'search',
      {
        field: 'params.query.raw',
        min_doc_count: 30,
        size: 10
      }
    ]
  end
  let(:rtu_top_queries) do
    instance_double(RtuTopQueries,
                    top_n: [['today term1', 55],
                            ['today term2', 54],
                            ['today term3', 4]])
  end

  context 'when searches with results exist for an affiliate' do
    before do
      expect(TopNExistsQuery).to receive(:new).with(*top_n_exists_args).and_call_original
      allow(RtuTopQueries).to receive(:new).and_return(rtu_top_queries)
    end

    it 'creates unprotected suggestions' do
      described_class.perform(affiliate.name, affiliate.id, date_int, 10)
      expect(SaytSuggestion.find_by(affiliate_id: affiliate.id, phrase: 'today term1').is_protected).to be false
    end

    it 'populates SaytSuggestions based on each entry for the given day' do
      described_class.perform(affiliate.name, affiliate.id, date_int, 10)
      expect(SaytSuggestion.find_by(affiliate_id: affiliate.id, phrase: 'today term1')).not_to be_nil
      expect(SaytSuggestion.find_by(affiliate_id: affiliate.id, phrase: 'today term2')).not_to be_nil
      expect(SaytSuggestion.find_by(phrase: 'yesterday term1')).to be_nil
    end

    context 'when SaytSuggestion already exists for an affiliate' do
      before do
        SaytSuggestion.create!(phrase: 'today term1', popularity: 17, affiliate_id: affiliate.id)
      end

      it 'updates the popularity field with the new count' do
        described_class.perform(affiliate.name, affiliate.id, date_int, 10)
        expect(SaytSuggestion.find_by(affiliate_id: affiliate.id, phrase: 'today term1').popularity).to eq(55)
      end
    end

    context 'when suggestions exist that have been marked as deleted' do
      before do
        SaytSuggestion.create!(
          phrase: 'today term1',
          affiliate: affiliate,
          deleted_at: Time.current,
          is_protected: true,
          popularity: SaytSuggestion::MAX_POPULARITY
        )
      end

      it 'does not create a new suggestion, and leaves the old suggestion alone' do
        described_class.perform(affiliate.name, affiliate.id, date_int, 10)
        suggestion = SaytSuggestion.find_by(affiliate_id: affiliate.id, phrase: 'today term1')
        expect(suggestion.deleted_at).not_to be_nil
        expect(suggestion.popularity).to eq(SaytSuggestion::MAX_POPULARITY)
      end
    end

    context 'when SaytFilters exist' do
      before do
        SaytFilter.create!(phrase: 'term2')
      end

      it 'applies SaytFilters to each eligible term' do
        described_class.perform(affiliate.name, affiliate.id, date_int, 10)
        expect(SaytSuggestion.find_by(affiliate_id: affiliate.id, phrase: 'today term2')).to be_nil
      end
    end

    context 'when computing for the current day' do
      before do
        allow(Date).to receive(:current).and_return Date.parse('2014-06-26')
        allow(Time).to receive(:now).and_return Time.utc(2014, 6, 26, 8, 2, 1)
      end

      it "factors in the time of day to compute a projected run rate for the term's popularity that day" do
        described_class.perform(affiliate.name, affiliate.id, date_int, 10)
        expect(SaytSuggestion.find_by(affiliate_id: affiliate.id, phrase: 'today term1').popularity).to eq(164)
      end
    end
  end
end
