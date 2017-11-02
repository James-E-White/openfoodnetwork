require 'spec_helper'
require 'open_food_network/cached_products_renderer'

module OpenFoodNetwork
  describe CachedProductsRenderer do
    let(:distributor) { double(:distributor, id: 123) }
    let(:order_cycle) { double(:order_cycle, id: 456) }
    let(:cpr) { CachedProductsRenderer.new(distributor, order_cycle) }

    describe "fetching cached products JSON" do
      context "when in testing / development" do
        let(:products_renderer) do
          double(ProductsRenderer, products_json: 'uncached products')
        end

        before do
          allow(ProductsRenderer)
            .to receive(:new)
            .with(distributor, order_cycle) { products_renderer }
        end

        it "returns uncaches products JSON" do
          expect(cpr.products_json).to eq 'uncached products'
        end
      end

      context "when in production / staging" do
        before do
          allow(Rails.env).to receive(:production?) { true }
        end

        describe "when the distribution is not set" do
          let(:cpr) { CachedProductsRenderer.new(nil, nil) }

          it "raises an exception and returns no products" do
            expect { cpr.products_json }.to raise_error CachedProductsRenderer::NoProducts
          end
        end

        describe "when the products JSON is already cached" do
          before do
            Rails.cache.write "products-json-#{distributor.id}-#{order_cycle.id}", 'products'
          end

          it "returns the cached JSON" do
            expect(cpr.products_json).to eq 'products'
          end

          it "raises an exception when there are no products" do
            Rails.cache.write "products-json-#{distributor.id}-#{order_cycle.id}", nil
            expect { cpr.products_json }.to raise_error CachedProductsRenderer::NoProducts
          end
        end

        describe "when the products JSON is not cached" do
          let(:cache_key) { "products-json-#{distributor.id}-#{order_cycle.id}" }
          let(:cached_json) { Rails.cache.read(cache_key) }
          let(:cache_present) { Rails.cache.exist?(cache_key) }
          let(:products_renderer) do
            double(ProductsRenderer, products_json: 'fresh products')
          end

          before do
            Rails.cache.delete(cache_key)

            allow(ProductsRenderer)
              .to receive(:new)
              .with(distributor, order_cycle) { products_renderer }
          end

          describe "when there are products" do
            it "returns products as JSON" do
              expect(cpr.products_json).to eq 'fresh products'
            end

            it "caches the JSON" do
              cpr.products_json
              expect(cached_json).to eq 'fresh products'
            end

            it "logs a warning" do
              cpr.should_receive :log_warning
              cpr.products_json
            end
          end

          describe "when there are no products" do
            let(:products_renderer) { double(ProductsRenderer) }

            before do
              allow(products_renderer).to receive(:products_json).and_raise ProductsRenderer::NoProducts

              allow(ProductsRenderer)
                .to receive(:new)
                .with(distributor, order_cycle) { products_renderer }
            end

            it "raises an error" do
              expect { cpr.products_json }.to raise_error CachedProductsRenderer::NoProducts
            end

            it "caches the products as nil" do
              expect { cpr.products_json }.to raise_error CachedProductsRenderer::NoProducts
              expect(cache_present).to be
              expect(cached_json).to be_nil
            end

            it "logs a warning" do
              cpr.should_receive :log_warning
              expect { cpr.products_json }.to raise_error CachedProductsRenderer::NoProducts
            end
          end
        end
      end
    end

    describe "logging a warning" do
      it "logs a warning when in production" do
        Rails.env.stub(:production?) { true }
        expect(Bugsnag).to receive(:notify)
        cpr.send(:log_warning)
      end

      it "logs a warning when in staging" do
        Rails.env.stub(:production?) { false }
        Rails.env.stub(:staging?) { true }
        expect(Bugsnag).to receive(:notify)
        cpr.send(:log_warning)
      end

      it "does not log a warning in development or test" do
        expect(Bugsnag).to receive(:notify).never
        cpr.send(:log_warning)
      end
    end

    describe "fetching uncached products from ProductsRenderer" do
      let(:pr) { double(:products_renderer, products_json: 'uncached products') }

      before do
        ProductsRenderer.stub(:new) { pr }
      end

      it "returns the uncached products" do
        expect(cpr.send(:uncached_products_json)).to eq 'uncached products'
      end
    end
  end
end
