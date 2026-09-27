# 2026-09-27 Next Steps: E2E Testing and Continuous Refactoring

This document outlines the current plan for continuous architectural decoupling, refactoring, and stability enhancement, following the initial release of `v1.28.0`.

## 1. 完善 E2E (端到端) 测试用例 (Completed)
- **User Tags**: Filled out the `e2e/user-tags.spec.js` skeleton to test tag endorsements, proposals, and inbox management flows.
- **Interest Onboarding**: Completed `e2e/interest-onboarding.spec.js` to cover onboarding page navigation, catalogue selection, and form submission.
- **Flying Chess Achievements**: Implemented `e2e/flying-chess.spec.js` to verify achievement board visibility, token redemption, and profile visibility toggling.

## 2. 持续的架构解耦与重构 (Continuous Architectural Decoupling)

Following the successful refactoring of the `RecommendationEngine` God Object (v1.28.0) and `community-discovery-panel.gjs` (v1.27.0), the following legacy components have been identified as candidates for extraction to reduce complexity:

### A. 后端: `DynamicFeed` 模块解耦 (Completed)
`lib/where_is_my_friends/dynamic_feed.rb` was refactored from ~500 lines into a 223-line orchestrator delegating to four cohesive sub-components:
- `DynamicFeed::Queries`: Handles `#feed`, `#recent`, `#discover`, and `#latest_by_user_ids`.
- `DynamicFeed::Publisher`: Manages `#create` and `#validate_content!`.
- `DynamicFeed::Reactor`: Manages `#react`, `#unreact`, and notification sync.
- `DynamicFeed::Serializer`: Centralizes `#serialize_many` and view building.

### B. 前端: `where-is-my-friends-results-panel.gjs` 组件拆分 (Completed)
- Extracted member rendering logic into a dedicated `<CommunityMemberCard>` (`assets/javascripts/discourse/components/community-member-card.gjs`) component.
- Moved avatar-related helpers (`hasAvatarFrame`, `isLevel7`, `pillModifier`, `roleBadge`) down to the new `CommunityMemberCard`.

### C. 后端: `NextAction` 路由选择器重构 (Completed)
`lib/where_is_my_friends/next_action.rb` was refactored from 336 lines into a 153-line orchestrator delegating to specialized evaluator classes under `lib/where_is_my_friends/next_action/evaluators/`:
- `NextAction::Evaluators::IncomingInvitation`: Evaluates pending incoming invitations.
- `NextAction::Evaluators::AcceptedConversation`: Evaluates accepted PM conversations awaiting follow-up.
- `NextAction::Evaluators::Onboarding`: Evaluates interest onboarding pending state.
- `NextAction::Evaluators::Recommendation`: Evaluates recommended topics or member profiles based on recent public interaction.
- `NextAction::Evaluators::Dynamic`: Evaluates recent dynamics.

---
*These changes aim to eliminate the remaining N+1 query hotspots and reduce cognitive load during subsequent feature development.*
