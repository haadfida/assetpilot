# Agent evals: evals/cases.jsonl, graded deterministically on tool selection, arguments, tool outcomes,
# database state and (optionally) answer facts. See evals/README section in the project README.
#
#   Evals::Validator  offline: checks every case against the seed data and the tool schemas, and runs each
#                     case's oracle trajectory through the real tools and the grader (no API key needed)
#   Evals::Live       live: runs Agent::Runner per case inside a rolled-back transaction (needs a key)
#   Evals::Grader     the deterministic grader, shared by both modes and self-tested in spec/evals
#   Evals::Judge      optional LLM-judge rubric for answer quality (--judge), on a cheaper model
module Evals
  ROOT = Rails.root.join("evals")
  CASES_PATH = ROOT.join("cases.jsonl")
  RESULTS_DIR = ROOT.join("results")

  # Every case runs against the deterministic seed (SeedData) with the clock frozen here, the same instant
  # the replay fixtures were recorded at, so "overdue", "expired" and "two weeks from today" never drift.
  AS_OF = Replays::Builder::AS_OF

  TAGS = %w[read write impact refusal out-of-scope ambiguous error-recovery].freeze

  module_function

  def load_cases(path = CASES_PATH) = Case.load_file(path)
end
