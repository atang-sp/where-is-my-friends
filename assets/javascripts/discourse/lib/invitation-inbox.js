import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

export const DEFAULT_SAFETY_ITEMS = Object.freeze([
  "ssc_consensus",
  "pure_practice",
  "safeword_mechanism",
  "body_safety",
  "aftercare",
  "public_first_meet",
]);

export default class InvitationInbox {
  @tracked success = null;
  @tracked incomingInvitations = [];
  @tracked outgoingInvitations = [];
  @tracked legacyPracticeBookmarks = [];
  @tracked invitationTarget = null;
  @tracked invitationInterestId = null;
  @tracked invitationProposedAt = "";
  @tracked invitationNote = "";
  @tracked invitationSafetyItems = [...DEFAULT_SAFETY_ITEMS];
  @tracked loading = false;
  @tracked error = null;

  constructor({ transport = ajax, inviteTo = null } = {}) {
    this.transport = transport;
    this.inviteTo = inviteTo;
    this.intents = Object.freeze({
      initialize: this.initialize,
      open: this.openInvitation,
      close: this.closeInvitation,
      changeDraft: this.changeDraft,
      send: this.sendInvitation,
      respond: this.respond,
    });
  }

  get view() {
    return {
      loading: this.loading,
      error: this.error,
      success: this.success,
      state: {
        busy: this.loading,
        legacy: {
          bookmarks: this.legacyPracticeBookmarks,
        },
        composer: {
          target: this.invitationTarget,
          interestId: this.invitationInterestId,
          interests: this.invitationInterests,
          proposedAt: this.invitationProposedAt,
          note: this.invitationNote,
          safetyItems: this.invitationSafetyItems,
          preview: this.invitationPreview,
        },
        inbox: {
          incoming: this.incomingInvitations,
          outgoing: this.outgoingInvitations,
        },
      },
    };
  }

  get invitationInterests() {
    return this.invitationTarget?.invitation_interests ?? [];
  }

  get selectedInvitationInterest() {
    return this.invitationInterests.find(
      (interest) => interest.id === this.invitationInterestId
    );
  }

  get invitationPreview() {
    if (!this.invitationTarget || !this.selectedInvitationInterest) {
      return "";
    }

    return i18n("where_is_my_friends.practice_invitations.preset_message", {
      username: this.invitationTarget.username,
      interest: this.selectedInvitationInterest.name,
    });
  }

  @action
  async initialize() {
    this.loading = true;
    this.error = null;
    try {
      await this.loadInvitations();
    } catch (error) {
      this.error = this.errorMessage(error);
    }

    await this.loadLegacyPracticeBookmarks();
    await this.openInvitationFromQuery();
    this.loading = false;
  }

  @action
  openInvitation(user) {
    const interests = user.invitation_interests ?? [];
    if (interests.length === 0) {
      return;
    }

    this.invitationTarget = user;
    this.invitationInterestId = interests[0].id;
    this.invitationProposedAt = "";
    this.invitationNote = "";
    this.invitationSafetyItems = [...DEFAULT_SAFETY_ITEMS];
    this.success = null;
    this.error = null;
  }

  @action
  closeInvitation() {
    this.invitationTarget = null;
    this.invitationInterestId = null;
    this.invitationProposedAt = "";
    this.invitationNote = "";
    this.invitationSafetyItems = [...DEFAULT_SAFETY_ITEMS];
  }

  @action
  changeDraft(patch) {
    if (Object.hasOwn(patch, "interestId")) {
      this.invitationInterestId = Number(patch.interestId);
    }
    if (Object.hasOwn(patch, "proposedAt")) {
      this.invitationProposedAt = patch.proposedAt;
    }
    if (Object.hasOwn(patch, "note")) {
      this.invitationNote = patch.note;
    }
    if (Object.hasOwn(patch, "safetyItems")) {
      this.invitationSafetyItems = patch.safetyItems;
    }
  }

  @action
  async sendInvitation() {
    if (this.loading || !this.invitationTarget || !this.invitationInterestId) {
      return;
    }

    this.loading = true;
    this.error = null;
    try {
      const response = await this.transport(
        "/where-is-my-friends/practice-invitations.json",
        {
          type: "POST",
          data: {
            recipient_id: this.invitationTarget.id,
            tag_id: this.invitationInterestId,
            proposed_at: this.invitationProposedAt
              ? new Date(this.invitationProposedAt).toISOString()
              : null,
            note: this.invitationNote,
            safety_items: this.invitationSafetyItems,
          },
        }
      );
      this.outgoingInvitations = [
        response.invitation,
        ...this.outgoingInvitations,
      ];
      this.success = i18n("where_is_my_friends.practice_invitations.sent");
      this.closeInvitation();
    } catch (error) {
      this.error = this.errorMessage(error);
    } finally {
      this.loading = false;
    }
  }

  @action
  async respondToInvitation(invitation, responseName) {
    if (this.loading || invitation.status !== "pending") {
      return;
    }

    this.loading = true;
    this.error = null;
    try {
      const response = await this.transport(
        `/where-is-my-friends/practice-invitations/${invitation.id}/${responseName}.json`,
        { type: "PUT" }
      );
      this.incomingInvitations = this.incomingInvitations.map((entry) =>
        entry.id === invitation.id ? response.invitation : entry
      );
    } catch (error) {
      this.error = this.errorMessage(error);
    } finally {
      this.loading = false;
    }
  }

  async loadInvitations() {
    const response = await this.transport(
      "/where-is-my-friends/practice-invitations.json"
    );
    this.incomingInvitations = response.incoming ?? [];
    this.outgoingInvitations = response.outgoing ?? [];
  }

  async loadLegacyPracticeBookmarks() {
    try {
      const response = await this.transport(
        "/where-is-my-friends/legacy-practice-bookmarks.json"
      );
      this.legacyPracticeBookmarks = response.bookmarks ?? [];
    } catch {
      // The legacy table may not exist on a fresh installation.
    }
  }

  @action
  async respondToLegacyBookmark(bookmark, responseName) {
    if (this.loading || bookmark.state !== "needs_reconfirmation") {
      return;
    }

    this.loading = true;
    this.error = null;
    try {
      const response = await this.transport(
        `/where-is-my-friends/legacy-practice-bookmarks/${bookmark.id}/${responseName}.json`,
        { type: "PUT" }
      );
      this.legacyPracticeBookmarks = this.legacyPracticeBookmarks.map(
        (entry) => (entry.id === bookmark.id ? response.bookmark : entry)
      );
    } catch (error) {
      this.error = this.errorMessage(error);
    } finally {
      this.loading = false;
    }
  }

  @action
  respond(kind, entry, responseName) {
    return {
      invitation: this.respondToInvitation,
      legacy: this.respondToLegacyBookmark,
    }[kind]?.(entry, responseName);
  }

  async openInvitationFromQuery() {
    if (!this.inviteTo) {
      return;
    }

    try {
      const response = await this.transport(
        "/where-is-my-friends/practice-invitations/availability.json",
        { data: { username: this.inviteTo } }
      );
      if (response.available) {
        this.openInvitation({
          id: response.recipient_id,
          username: response.username,
          name: response.name,
          invitation_interests: response.interests,
        });
      }
    } catch {
      // The target may no longer be available; keep the main page usable.
    }
  }

  errorMessage(error) {
    const response = error?.jqXHR?.responseJSON ?? error?.responseJSON;
    return (
      response?.errors?.[0] ??
      i18n("where_is_my_friends.interests.generic_error")
    );
  }
}
