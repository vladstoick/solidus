require 'spec_helper'

RSpec.describe Spree::Tax::ItemAdjuster do
  subject(:adjuster) { described_class.new(item) }
  let(:order) { create(:order) }
  let(:item) { create(:line_item, order: order) }

  def tax_adjustments
    item.adjustments.tax.to_a
  end

  describe 'initialization' do
    it 'sets order to item order' do
      expect(adjuster.order).to eq(item.order)
    end

    it 'sets adjustable' do
      expect(adjuster.item).to eq(item)
    end
  end

  shared_examples_for 'untaxed item' do
    it 'creates no adjustments' do
      adjuster.adjust!
      expect(tax_adjustments).to eq([])
    end

    context 'with an existing tax adjustment' do
      let!(:existing_adjustment) { create(:tax_adjustment, adjustable: item) }

      it 'removes the existing adjustment' do
        adjuster.adjust!
        aggregate_failures do
          expect(tax_adjustments).to eq([])
          expect(Spree::Adjustment).to_not be_exists(existing_adjustment.id)
        end
      end
    end
  end

  describe '#adjust!' do
    before do
      expect(order).to receive(:tax_address).at_least(:once).and_return(address)
    end

    context 'when the order has no tax zone' do
      let(:address) { Spree::Tax::TaxLocation.new }

      it_behaves_like 'untaxed item'
    end

    context 'when the order has a taxable address' do
      let(:item) { build_stubbed :line_item, order: order }
      let(:address) { order.tax_address }

      before do
        expect(Spree::TaxRate).to receive(:for_address).with(order.tax_address).and_return(rates_for_order_zone)
      end

      context 'when there are no matching rates' do
        let(:rates_for_order_zone) { [] }

        it_behaves_like 'untaxed item'
      end

      context 'when there are matching rates for the zone' do
        context "and there matching tax rates for the item" do
          let(:item_tax_category) { build(:tax_category) }
          let(:item) { build_stubbed :line_item, order: order, tax_category: item_tax_category }
          let(:rate_1) { create :tax_rate, tax_categories: [item_tax_category] }
          let(:rate_2) { create :tax_rate }
          let(:rate_3) { create :tax_rate, tax_categories: [item_tax_category, build(:tax_category)] }
          let(:rates_for_order_zone) { [rate_1, rate_2, rate_3] }

          it 'creates an adjustment for every matching rate' do
            adjuster.adjust!
            expect(tax_adjustments.length).to eq(2)
          end

          it 'creates adjustments only for matching rates' do
            adjuster.adjust!
            expect(tax_adjustments.map(&:source)).to match_array([rate_1, rate_3])
          end
        end
      end
    end
  end
end
