require 'rails_helper'

RSpec.describe GraphToTerms do
  let(:klass) { Vocabulary }
  let(:rdf_statement) { RDF::Statement.new(nil, nil, klass.type)}
  let(:graph) { instance_double("RDF::Graph") }
  let(:repository) { instance_double("StandardRepository") }
  let(:triples) { [rdf_statement]}
  subject { GraphToTerms.new(repository, graph) }

  describe "#type_of_graph" do
    context "each type of terms" do
      [Vocabulary, Predicate, Term, Concept, CorporateName, Geographic, PersonalName, Title, Topic].each do |x|
        let(:klass) { x }
        it "#{x} should return the proper class" do
          subject.type_of_graph(triples)
          expect(subject.klass).to eq(klass)
        end
      end
    end
  end
end