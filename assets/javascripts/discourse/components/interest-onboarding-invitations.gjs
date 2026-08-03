import { concat, fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { eq } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";

export default <template>
      {{#if @legacyPracticeBookmarks.length}}
        <section class="interest-onboarding__legacy-bookmarks">
          <div>
            <p class="interest-onboarding__eyebrow">{{i18n
                "where_is_my_friends.legacy_practice_bookmarks.eyebrow"
              }}</p>
            <h2>{{i18n
                "where_is_my_friends.legacy_practice_bookmarks.title"
              }}</h2>
            <p>{{i18n
                "where_is_my_friends.legacy_practice_bookmarks.description"
              }}</p>
          </div>
          <div class="interest-onboarding__legacy-bookmark-list">
            {{#each @legacyPracticeBookmarks as |bookmark|}}
              <article data-test-legacy-practice-bookmark={{bookmark.id}}>
                <div>
                  <h3>@{{bookmark.target.username}}</h3>
                  {{#if bookmark.mutual_history}}
                    <span>{{i18n
                        "where_is_my_friends.legacy_practice_bookmarks.mutual_history"
                      }}</span>
                  {{/if}}
                </div>
                {{#if (eq bookmark.state "needs_reconfirmation")}}
                  <p>{{i18n
                      "where_is_my_friends.legacy_practice_bookmarks.no_auto_invite"
                    }}</p>
                  <div class="interest-onboarding__invitation-actions">
                    <DButton
                      @action={{fn
                        @respondToLegacyBookmark
                        bookmark
                        "reconfirm"
                      }}
                      @label="where_is_my_friends.legacy_practice_bookmarks.reconfirm"
                      @icon="check"
                      @disabled={{@loading}}
                      class="btn-primary"
                      data-test-reconfirm-legacy-practice={{bookmark.id}}
                    />
                    <DButton
                      @action={{fn
                        @respondToLegacyBookmark
                        bookmark
                        "dismiss"
                      }}
                      @label="where_is_my_friends.legacy_practice_bookmarks.dismiss"
                      @disabled={{@loading}}
                      class="btn-flat"
                      data-test-dismiss-legacy-practice={{bookmark.id}}
                    />
                  </div>
                {{else}}
                  <span class="interest-onboarding__invitation-status">
                    {{i18n
                      (concat
                        "where_is_my_friends.legacy_practice_bookmarks.status."
                        bookmark.state
                      )
                    }}
                  </span>
                {{/if}}
              </article>
            {{/each}}
          </div>
        </section>
      {{/if}}

      {{#if @invitationTarget}}
        <section
          class="interest-onboarding__invitation-form"
          data-test-practice-invitation-form
        >
          <div>
            <p class="interest-onboarding__eyebrow">{{i18n
                "where_is_my_friends.practice_invitations.eyebrow"
              }}</p>
            <h2>{{i18n
                "where_is_my_friends.practice_invitations.form_title"
                username=@invitationTarget.username
              }}</h2>
            <p>{{i18n
                "where_is_my_friends.practice_invitations.one_to_one_notice"
              }}</p>
          </div>

          <label>
            <span>{{i18n
                "where_is_my_friends.practice_invitations.interest"
              }}</span>
            <select
              value={{@invitationInterestId}}
              data-test-practice-invitation-interest
              {{on "change" @updateInvitationInterest}}
            >
              {{#each @invitationInterests as |interest|}}
                <option value={{interest.id}}>{{interest.name}}</option>
              {{/each}}
            </select>
          </label>

          <label>
            <span>{{i18n
                "where_is_my_friends.practice_invitations.proposed_time"
              }}</span>
            <input
              type="datetime-local"
              value={{@invitationProposedAt}}
              data-test-practice-invitation-time
              {{on "input" @updateInvitationProposedAt}}
            />
          </label>

          <label>
            <span>{{i18n
                "where_is_my_friends.practice_invitations.note"
              }}</span>
            <textarea
              maxlength="500"
              value={{@invitationNote}}
              data-test-practice-invitation-note
              {{on "input" @updateInvitationNote}}
            ></textarea>
          </label>

          <p
            class="interest-onboarding__invitation-preview"
            data-test-practice-invitation-preview
          >
            {{@invitationPreview}}
          </p>

          <div class="interest-onboarding__form-actions">
            <DButton
              @action={{@sendInvitation}}
              @label="where_is_my_friends.practice_invitations.send"
              @icon="paper-plane"
              @disabled={{@loading}}
              class="btn-primary"
              data-test-send-practice-invitation
            />
            <DButton
              @action={{@closeInvitation}}
              @label="where_is_my_friends.practice_invitations.cancel"
              @disabled={{@loading}}
              class="btn-flat"
              data-test-cancel-practice-invitation
            />
          </div>
        </section>
      {{/if}}

      {{#if @incomingInvitations.length}}
        <section class="interest-onboarding__invitations">
          <h2>{{i18n
              "where_is_my_friends.practice_invitations.incoming"
            }}</h2>
          <div class="interest-onboarding__invitation-list">
            {{#each @incomingInvitations as |invitation|}}
              <article data-test-incoming-invitation={{invitation.id}}>
                <h3>@{{invitation.sender.username}}</h3>
                <p>{{invitation.preset_message}}</p>
                {{#if invitation.proposed_at}}
                  <p>{{i18n
                      "where_is_my_friends.practice_invitations.proposed_time_value"
                      time=invitation.proposed_at
                    }}</p>
                {{/if}}
                {{#if invitation.note}}
                  <blockquote>{{invitation.note}}</blockquote>
                {{/if}}
                {{#if (eq invitation.status "pending")}}
                  <div class="interest-onboarding__invitation-actions">
                    <DButton
                      @action={{fn
                        @respondToInvitation
                        invitation
                        "accept"
                      }}
                      @label="where_is_my_friends.practice_invitations.accept"
                      @icon="check"
                      @disabled={{@loading}}
                      class="btn-primary"
                      data-test-accept-practice-invitation={{invitation.id}}
                    />
                    <DButton
                      @action={{fn
                        @respondToInvitation
                        invitation
                        "decline"
                      }}
                      @label="where_is_my_friends.practice_invitations.decline"
                      @disabled={{@loading}}
                      class="btn-default"
                      data-test-decline-practice-invitation={{invitation.id}}
                    />
                    <DButton
                      @action={{fn
                        @respondToInvitation
                        invitation
                        "ignore"
                      }}
                      @label="where_is_my_friends.practice_invitations.ignore"
                      @disabled={{@loading}}
                      class="btn-flat"
                      data-test-ignore-practice-invitation={{invitation.id}}
                    />
                  </div>
                {{else if invitation.pm_url}}
                  <a href={{invitation.pm_url}}>{{i18n
                      "where_is_my_friends.practice_invitations.open_pm"
                    }}</a>
                {{else}}
                  <span class="interest-onboarding__invitation-status">
                    {{i18n
                      (concat
                        "where_is_my_friends.practice_invitations.status."
                        invitation.status
                      )
                    }}
                  </span>
                {{/if}}
              </article>
            {{/each}}
          </div>
        </section>
      {{/if}}

      {{#if @outgoingInvitations.length}}
        <details class="interest-onboarding__outgoing-invitations">
          <summary>{{i18n
              "where_is_my_friends.practice_invitations.outgoing"
            }}</summary>
          {{#each @outgoingInvitations as |invitation|}}
            <p data-test-outgoing-invitation={{invitation.id}}>
              @{{invitation.recipient.username}} ·
              {{invitation.interest.name}}
              ·
              {{i18n
                (concat
                  "where_is_my_friends.practice_invitations.status."
                  invitation.status
                )
              }}
            </p>
          {{/each}}
        </details>
      {{/if}}
</template>
