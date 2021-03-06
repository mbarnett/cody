require 'rails_helper'

RSpec.describe ReviewRule, type: :model do
  it { is_expected.to validate_presence_of :name }
  it { is_expected.to validate_presence_of :reviewer }
  it { is_expected.to validate_presence_of :repository }

  let(:rule) { build :review_rule, reviewer: reviewer }

  describe ".for_repository" do
    let!(:rule1) { create :review_rule_always, repository: "aergonaut/testrepo" }
    let!(:rule2) { create :review_rule_always, repository: "aergonaut/cody" }

    subject { ReviewRule.for_repository("aergonaut/cody") }

    it { is_expected.to contain_exactly(rule2) }
    it { is_expected.to_not include(rule1) }
  end

  describe "#possible_reviewers" do
    context "when reviewer is a team ID" do
      let(:reviewer) { "1234" }

      before do
        stub_request(:get, %r{https?://api.github.com/teams/1234/members}).to_return(
          status: 200,
          headers: { 'Content-Type' => 'application/json' },
          body: File.open(Rails.root.join("spec", "fixtures", "team_members.json"))
        )
      end

      it "returns the list of team member logins" do
        expected_team_members = %w(aergonaut BrentW farrspace deepthisunder
          yatish27 h4hardikonly mityaz mpukas nazarik vovka torumori offtop)
        expect(rule.possible_reviewers).to contain_exactly(*expected_team_members)
      end
    end

    context "when reviewer is a username" do
      let(:reviewer) { "aergonaut" }

      it "just returns the username" do
        expect(rule.possible_reviewers).to eq(["aergonaut"])
      end
    end
  end

  describe "#add_reviewer" do
    let(:pr) { create :pull_request, pending_reviews: pending_reviews }

    let(:rule) { build :review_rule, reviewer: reviewer }

    context "when the reviewer is not already on the review list" do
      before do
        stub_request(:get, %r{https?://api.github.com/repos/aergonaut/testrepo/pulls/#{pr.number}/commits}).to_return(
          status: 200,
          headers: { 'Content-Type' => 'application/json' },
          body: "[]"
        )
      end

      let(:reviewer) { "BrentW" }

      let(:pending_reviews) { ["aergonaut"] }

      it "returns the username that was added" do
        expect(rule.add_reviewer(pr)).to eq("BrentW")
      end

      it "adds the reviewer to the pending reviews" do
        expect { rule.add_reviewer(pr) }.to change { pr.pending_reviews }
          .from(["aergonaut"]).to(["aergonaut", "BrentW"])
      end
    end

    context "when the reviewer is already on the review list" do
      before do
        stub_request(:get, %r{https?://api.github.com/repos/aergonaut/testrepo/pulls/#{pr.number}/commits}).to_return(
          status: 200,
          headers: { 'Content-Type' => 'application/json' },
          body: "[]"
        )
      end
      let(:reviewer) { "aergonaut" }

      let(:pending_reviews) { ["aergonaut"] }

      it "returns the reviewer" do
        expect(rule.add_reviewer(pr)).to eq("aergonaut")
      end

      it "does not change pending reviews" do
        expect { rule.add_reviewer(pr) }.to_not change { pr.pending_reviews }
      end
    end
    
    context "when the reviewer is the commit author" do
      before do
        stub_request(:get, %r{https?://api.github.com/repos/aergonaut/testrepo/pulls/#{pr.number}/commits}).to_return(
          status: 200,
          headers: { 'Content-Type' => 'application/json' },
          body: File.open(Rails.root.join("spec", "fixtures", "pull_request_commits.json"))
        )
      end

      context "and there are no other reviewer" do
        let(:reviewer) { "aergonaut" }

        let(:pending_reviews) { ["aergonaut"] }

        it "returns the reviewer" do
          expect(rule.add_reviewer(pr)).to eq('aergonaut')
        end

        it "does not change pending reviews" do
          expect { rule.add_reviewer(pr) }.to_not change { pr.pending_reviews }
        end
      end

      context "and there is another reviewer" do
        before do
          allow_any_instance_of(ReviewRule).to receive(:possible_reviewers).and_return(['aergonaut','mrpasquini'])
        end
        let(:reviewer) { } # stubbed possible_reviewers method instead
        let(:pending_reviews) { ["brentW"] }

        it "returns the other reviewer" do
          expect(rule.add_reviewer(pr)).to eq('mrpasquini')
        end
      end
      
    end
  end

  describe "#apply" do
    let(:pull_request_hash) do
      {
        "number" => 42,
        'base' => {'repo' => {'full_name' => 'aergonaut/testrepo'}}
      }
    end

    let(:rule) { build :review_rule, reviewer: "aergonaut" }

    before do
      stub_request(:get, %r{https?://api.github.com/repos/aergonaut/testrepo/pulls/#{pull_request_hash['number']}/commits}).to_return(
        status: 200,
        headers: { 'Content-Type' => 'application/json' },
        body: File.open(Rails.root.join("spec", "fixtures", "pull_request_commits.json"))
      )

      create :pull_request, number: pull_request_hash['number'], repository: 'aergonaut/testrepo'

      expect(rule).to receive(:matches?).with(pull_request_hash).and_return(rule_matches)
    end

    context "when the rule matches" do
      let(:rule_matches) { "foobar" }

      it "calls add_reviewer" do
        expect(rule).to receive(:add_reviewer)
        rule.apply(pull_request_hash)
      end

      it "returns a successful ReviewRuleResult" do
        result = rule.apply(pull_request_hash)
        expect(result).to be_success
        expect(result.reviewer).to eq(rule.reviewer)
      end
    end

    context "when the rule does not match" do
      let(:rule_matches) { nil }

      it "does not call add_reviewer" do
        expect(rule).to_not receive(:add_reviewer)
        rule.apply(pull_request_hash)
      end

      it "returns a failed ReviewRuleResult" do
        result = rule.apply(pull_request_hash)
        expect(result).to be_failure
        expect(result.reviewer).to be_nil
      end
    end
  end
end
