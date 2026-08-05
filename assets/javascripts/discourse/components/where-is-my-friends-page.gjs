import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { next } from "@ember/runloop";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { relativeAge } from "discourse/lib/formatter";
import { clipboardCopy } from "discourse/lib/utilities";
import { i18n } from "discourse-i18n";
import { normalizeCityClient } from "../lib/where-is-my-friends-city";
import { getCurrentPositionAsync } from "../lib/where-is-my-friends-geolocation";
import LocationModeDialog from "./location-mode-dialog";
import VirtualLocationPicker from "./virtual-location-picker";
import WhereIsMyFriendsResultsPanel from "./where-is-my-friends-results-panel";
import WhereIsMyFriendsSetupPanel from "./where-is-my-friends-setup-panel";

export default class WhereIsMyFriendsPage extends Component {
  @service currentUser;
  @service modal;
  @service router;
  @service siteSettings;

  @tracked city;
  @tracked region;
  @tracked location;
  @tracked discoveryState;
  @tracked users = [];
  @tracked cityGroups = [];
  @tracked loading = false;
  @tracked error = null;
  @tracked gpsFallback = false;
  @tracked memberFilter = "";
  @tracked showRegion;
  @tracked inviteFeedback = null;
  @tracked notifyCity;
  @tracked notifyNearby;
  @tracked nearbyCityCount = 0;
  @tracked expandedRadius = false;
  @tracked originalRadiusKm = null;
  @tracked expandedRadiusKm = null;
  @tracked autoCity = null;
  @tracked activeFilters = {};
  @tracked networkPreview = null;
  @tracked previewLoading = false;
  @tracked selectedPreviewRadius = null;

  constructor() {
    super(...arguments);
    const autoCity =
      this.router.currentRoute?.queryParams?.auto_city ??
      new URLSearchParams(window.location.search).get("auto_city");
    this.city =
      this.args.model.location?.city ??
      autoCity ??
      this.args.model.profile_location ??
      "";
    this.autoCity = autoCity && !this.args.model.location ? autoCity : null;
    this.region = this.args.model.location?.region ?? "";
    this.showRegion = Boolean(this.region);
    this.location = this.args.model.location;
    this.discoveryState = this.args.model.state;
    this.notifyCity =
      this.currentUser?.user_option?.where_is_my_friends_notify_city ?? true;
    this.notifyNearby =
      this.currentUser?.user_option?.where_is_my_friends_notify_nearby ?? true;
  }

  get isSetup() {
    return this.discoveryState === "setup";
  }

  get isEmpty() {
    return this.discoveryState === "empty";
  }

  get availableUsers() {
    const username =
      this.currentUser?.username ?? this.args.model.current_user?.username;
    return this.users.filter((user) => user.username !== username);
  }

  get hasUsers() {
    return this.availableUsers.length > 0;
  }

  get showMemberFilter() {
    return this.availableUsers.length >= 10;
  }

  get chatEnabled() {
    return this.siteSettings.chat_enabled && this.currentUser?.has_chat_enabled;
  }

  get visibleUsers() {
    const bandOrder = {
      same_city: 0,
      under_5: 1,
      nearby: 2,
      "5_to_20": 3,
      moderate: 4,
      over_20: 5,
      far: 6,
    };
    const query = this.memberFilter.trim().toLocaleLowerCase();
    const users = query
      ? this.availableUsers.filter((user) =>
          [user.name, user.username].some((value) =>
            value?.toLocaleLowerCase().includes(query)
          )
        )
      : this.availableUsers;

    const useChat = this.chatEnabled;
    const fields = this.filterableFields;
    return [...users]
      .sort(
        (a, b) =>
          (bandOrder[a.distance_band ?? "same_city"] ?? 99) -
          (bandOrder[b.distance_band ?? "same_city"] ?? 99)
      )
      .map((user) => {
        const lastActiveLabel = user.last_seen_at
          ? relativeAge(new Date(user.last_seen_at), { format: "tiny" })
          : null;
        let activityLabel = null;
        if (user.online) {
          activityLabel = i18n("where_is_my_friends.online_now");
        } else if (lastActiveLabel) {
          activityLabel = i18n("where_is_my_friends.seen_recently", {
            time: lastActiveLabel,
          });
        }

        return {
          ...user,
          distance_label:
            (user.distance_band ?? "same_city") === "same_city"
              ? null
              : i18n(
                  `where_is_my_friends.distance_bands.${user.distance_band}`
                ),
          action_url: useChat
            ? `/chat/new-message?recipients=${encodeURIComponent(user.username)}`
            : user.message_url,
          activity_label: activityLabel,
          custom_field_label: fields
            .map((f) => user.custom_fields?.[f.name])
            .filter(Boolean)
            .join(" / "),
          inactive: user.activity_status === "inactive",
        };
      });
  }

  get displayCityGroups() {
    const visibleUsers = new Map(
      this.visibleUsers.map((user) => [user.username, user])
    );
    const groups = this.cityGroups.length
      ? this.cityGroups
      : [
          {
            city: this.location?.city,
            city_key: this.location?.city,
            distance_band: "same_city",
            approximate_distance_km: null,
            recent_active_count: this.visibleUsers.filter(
              (user) => !user.inactive
            ).length,
            joined_count: this.visibleUsers.length,
            users: this.users,
            synthetic: true,
          },
        ];

    return groups
      .map((group) => {
        const users = group.users
          .map((user) => visibleUsers.get(user.username))
          .filter(Boolean);
        const sameCity = group.distance_band === "same_city";
        return {
          ...group,
          users,
          heading_label: sameCity
            ? i18n("where_is_my_friends.city_group_same", {
                city: group.city,
              })
            : i18n("where_is_my_friends.city_group_nearby", {
                city: group.city,
                distance: group.approximate_distance_km,
              }),
          counts_label: i18n("where_is_my_friends.city_group_counts", {
            active: group.recent_active_count,
            joined: group.joined_count,
          }),
        };
      })
      .filter((group) => group.users.length > 0);
  }

  get resultsSummary() {
    const count = this.availableUsers.length;
    return i18n(
      count === 1
        ? "where_is_my_friends.results_count_one"
        : "where_is_my_friends.results_count_other",
      {
        city: this.location.city,
        count,
        radius: this.expandedRadius
          ? this.expandedRadiusKm
          : this.discoveryRadiusKm,
      }
    );
  }

  get discoveryRadiusKm() {
    return (
      this.location?.discovery_radius_km ??
      this.args.model.settings?.default_discovery_radius_km ??
      100
    );
  }

  get discoveryRadiusOptions() {
    return (
      this.args.model.settings?.discovery_radius_options_km ?? [50, 100, 200]
    );
  }

  get discoveryRadiusButtons() {
    return this.discoveryRadiusOptions.map((radius) => ({
      radius,
      selected: radius === this.discoveryRadiusKm,
      label: i18n("where_is_my_friends.discovery_radius_option", { radius }),
    }));
  }

  get filterableFields() {
    return this.args.model.filterable_fields ?? [];
  }

  get hasFilterableFields() {
    return this.filterableFields.length > 0;
  }

  get hasActiveFilters() {
    return Object.keys(this.activeFilters).length > 0;
  }

  get filterGroups() {
    return this.filterableFields.map((field) => ({
      ...field,
      buttons: [
        {
          value: null,
          label: i18n("where_is_my_friends.filter_all"),
          selected: !this.activeFilters[field.key],
        },
        ...field.options.map((option) => ({
          value: option,
          label: option,
          selected: this.activeFilters[field.key] === option,
        })),
      ],
    }));
  }

  get participantProof() {
    const participants = this.args.model.active_participants;
    if (!participants || participants.suppressed) {
      return i18n("where_is_my_friends.participant_proof_generic");
    }

    if (participants.city_count) {
      return i18n("where_is_my_friends.global_stats", {
        count: participants.count,
        city_count: participants.city_count,
      });
    }

    return i18n("where_is_my_friends.participant_proof_count", {
      count: participants.count,
    });
  }

  get cityDirectory() {
    return this.args.model.city_directory ?? null;
  }

  get hasCityDirectory() {
    return Boolean(
      this.cityDirectory?.active?.length || this.cityDirectory?.growing?.length
    );
  }

  get cityOptions() {
    return (
      this.args.model.city_catalogue ?? this.args.model.city_suggestions ?? []
    );
  }

  get previewRadiusButtons() {
    return (this.networkPreview?.radius_options ?? []).map((option) => ({
      ...option,
      selected: option.radius_km === this.selectedPreviewRadius,
      label: i18n("where_is_my_friends.preview_radius_summary", {
        radius: option.radius_km,
        active: option.recent_active_count,
        joined: option.joined_count,
      }),
    }));
  }

  get previewJoinLabel() {
    return i18n("where_is_my_friends.join_preview_city", {
      city: this.networkPreview?.city?.city ?? this.city,
    });
  }

  get localTopicActionUrl() {
    return `/search?q=${encodeURIComponent(this.location?.city ?? "")}`;
  }

  get cityPreview() {
    const input = this.city.trim().toLowerCase();
    if (!input) {
      return null;
    }

    const normalizedInput = normalizeCityClient(input);
    const match = this.args.model.city_suggestions?.find(
      (suggestion) =>
        suggestion.city.toLowerCase() === input ||
        suggestion.city_key === normalizedInput
    );

    if (!Number.isFinite(match?.count) || match.count < 1) {
      return null;
    }

    const threshold =
      this.args.model.settings?.aggregate_privacy_threshold ?? 3;
    if (match.count < threshold) {
      return null;
    }

    return i18n("where_is_my_friends.city_member_count", {
      count: match.count,
      city: match.city,
    });
  }

  get cityNormalizationHint() {
    const raw = this.city.trim();
    if (!raw) {
      return null;
    }

    const normalized = normalizeCityClient(raw);
    const comparable = raw.replace(/\s+/g, " ").toLowerCase();
    if (normalized === comparable) {
      return null;
    }

    return i18n("where_is_my_friends.city_will_match_as", { normalized });
  }

  @action
  initialize() {
    void this.recordEvent("page_view");
    void this.recordEvent("directory_viewed");
    const notificationSource = new URLSearchParams(window.location.search).get(
      "notification"
    );
    if (notificationSource) {
      void this.recordEvent("notification_opened");
    }
    if (this.discoveryState === "ready") {
      void this.loadResults();
    }
  }

  @action
  updateCity(event) {
    this.city = event.target.value;
    this.networkPreview = null;
    this.selectedPreviewRadius = null;
  }

  @action
  previewCurrentCity() {
    return this.loadCityPreview(this.city);
  }

  @action
  previewSuggestedCity(city) {
    this.city = city;
    return this.loadCityPreview(city);
  }

  async loadCityPreview(city) {
    const requestedCity = city.trim();
    if (!requestedCity || this.previewLoading) {
      return;
    }

    this.previewLoading = true;
    this.error = null;
    try {
      const response = await ajax("/where-is-my-friends/cities/preview.json", {
        data: { city: requestedCity },
      });
      this.networkPreview = response;
      this.city = response.city?.city ?? requestedCity;
      this.selectedPreviewRadius =
        response.recommended_radius_km ??
        this.args.model.settings?.default_discovery_radius_km ??
        100;
      void this.recordEvent("city_previewed");
    } catch (error) {
      this.error = this.errorMessage(error);
    } finally {
      this.previewLoading = false;
    }
  }

  @action
  selectPreviewRadius(radiusKm) {
    this.selectedPreviewRadius = radiusKm;
  }

  @action
  updateRegion(event) {
    this.region = event.target.value;
  }

  @action
  revealRegion() {
    this.showRegion = true;
  }

  @action
  updateMemberFilter(event) {
    this.memberFilter = event.target.value;
  }

  @action
  async selectFilter(fieldKey, value) {
    const newFilters = { ...this.activeFilters };
    if (value === null) {
      delete newFilters[fieldKey];
    } else {
      newFilters[fieldKey] = value;
    }
    this.activeFilters = newFilters;
    await this.loadResults();
  }

  @action
  async saveCity() {
    if (!this.city.trim() || this.loading) {
      return;
    }

    this.loading = true;
    this.error = null;
    void this.recordEvent("setup_started", { location_mode: "city" });

    try {
      const response = await ajax("/where-is-my-friends/locations.json", {
        type: "POST",
        data: {
          city: this.city.trim(),
          region: this.region.trim(),
          discovery_mode: "city",
          discovery_radius_km:
            this.selectedPreviewRadius ?? this.discoveryRadiusKm,
          notify_city: this.notifyCity,
          notify_nearby: this.notifyNearby,
        },
      });
      this.location = response.location;
      this.discoveryState = response.state;
      this.networkPreview = null;
      void this.recordEvent("radius_confirmed", { location_mode: "city" });
      void this.recordEvent("location_saved", { location_mode: "city" });
      await this.loadResults();
    } catch (error) {
      this.error = this.errorMessage(error);
    } finally {
      this.loading = false;
    }
  }

  async loadResults() {
    this.loading = true;
    this.error = null;

    try {
      const data = {};
      for (const [key, value] of Object.entries(this.activeFilters)) {
        data[`filters[${key}]`] = value;
      }
      const response = await ajax(
        "/where-is-my-friends/locations/nearby.json",
        { data }
      );
      this.users = response.users ?? [];
      this.cityGroups = response.city_groups ?? [];
      this.nearbyCityCount = response.nearby_city_count ?? 0;
      this.expandedRadius = response.expanded_radius ?? false;
      this.originalRadiusKm = response.original_radius_km ?? null;
      this.expandedRadiusKm = response.expanded_radius_km ?? null;
      this.discoveryState = this.availableUsers.length > 0 ? "ready" : "empty";
      void this.recordEvent("results_viewed", {
        location_mode: this.location?.discovery_mode ?? "city",
        result_count: this.availableUsers.length,
      });
    } catch (error) {
      this.error = this.errorMessage(error);
    } finally {
      this.loading = false;
    }
  }

  @action
  async selectDiscoveryRadius(radiusKm) {
    if (!this.location || this.loading || radiusKm === this.discoveryRadiusKm) {
      return;
    }

    this.loading = true;
    this.error = null;
    try {
      const response = await ajax("/where-is-my-friends/locations.json", {
        type: "POST",
        data: {
          city: this.location.city,
          region: this.location.region ?? "",
          discovery_mode: this.location.discovery_mode ?? "city",
          discovery_radius_km: radiusKm,
        },
      });
      this.location = response.location;
      this.discoveryState = response.state;
      await this.loadResults();
    } catch (error) {
      this.error = this.errorMessage(error);
    } finally {
      this.loading = false;
    }
  }

  @action
  openAdvancedLocation() {
    this.gpsFallback = false;
    this.modal.show(LocationModeDialog, {
      model: {
        onGps: () => this.upgradeWithGps(),
        onMap: () => next(() => this.openMapPicker()),
      },
    });
  }

  @action
  openMapPicker() {
    this.modal.show(VirtualLocationPicker, {
      model: {
        settings: this.args.model.settings,
        onConfirm: (coordinates) => this.savePrecise("map", coordinates),
      },
    });
  }

  async upgradeWithGps() {
    this.loading = true;
    this.error = null;
    try {
      const position = await getCurrentPositionAsync();
      await this.savePrecise("gps", {
        latitude: position.coords.latitude,
        longitude: position.coords.longitude,
        location_accuracy: position.coords.accuracy,
      });
    } catch {
      this.gpsFallback = true;
      this.loading = false;
    }
  }

  async savePrecise(discoveryMode, coordinates) {
    this.loading = true;
    this.error = null;
    try {
      const response = await ajax("/where-is-my-friends/locations.json", {
        type: "POST",
        data: {
          city: this.location.city,
          region: this.location.region ?? "",
          discovery_mode: discoveryMode,
          ...coordinates,
        },
      });
      this.location = response.location;
      this.discoveryState = response.state;
      void this.recordEvent("location_saved", { location_mode: discoveryMode });
      await this.loadResults();
    } catch (error) {
      this.error = this.errorMessage(error);
    } finally {
      this.loading = false;
    }
  }

  @action
  editLocation() {
    this.discoveryState = "setup";
    this.showRegion = Boolean(this.region);
    this.users = [];
    this.cityGroups = [];
    this.memberFilter = "";
    this.activeFilters = {};
    this.gpsFallback = false;
  }

  @action
  async removeLocation() {
    if (this.loading) {
      return;
    }

    this.loading = true;
    this.error = null;
    try {
      await ajax("/where-is-my-friends/locations.json", { type: "DELETE" });
      void this.recordEvent("location_removed", {
        location_mode: this.location?.discovery_mode ?? "city",
      });
      this.location = null;
      this.users = [];
      this.cityGroups = [];
      this.discoveryState = "setup";
      this.memberFilter = "";
      this.activeFilters = {};
    } catch (error) {
      this.error = this.errorMessage(error);
    } finally {
      this.loading = false;
    }
  }

  @action
  trackConnection(eventName) {
    void this.recordEvent(eventName, {
      location_mode: this.location?.discovery_mode ?? "city",
    });
  }

  @action
  trackLocalTopicOpen() {
    void this.recordEvent("local_topic_opened", {
      location_mode: this.location?.discovery_mode ?? "city",
    });
  }

  @action
  trackLocalTopicCompose() {
    void this.recordEvent("local_topic_interacted", {
      location_mode: this.location?.discovery_mode ?? "city",
    });
  }

  async recordEvent(eventName, data = {}) {
    try {
      await ajax("/where-is-my-friends/events.json", {
        type: "POST",
        data: { event_name: eventName, ...data },
      });
    } catch {
      // Analytics must never block local discovery.
    }
  }

  @action
  async copyInvite() {
    try {
      const url = new URL("/where-is-my-friends", window.location);
      if (this.location?.city) {
        url.searchParams.set("auto_city", this.location.city);
      }
      await clipboardCopy(url.href);
      this.inviteFeedback = i18n("where_is_my_friends.invite_copied");
    } catch {
      this.inviteFeedback = i18n("where_is_my_friends.invite_copy_failed");
    }
  }

  @action
  async toggleNotifyCity() {
    this.notifyCity = !this.notifyCity;
    try {
      await ajax(`/u/${this.currentUser.username}.json`, {
        type: "PUT",
        data: {
          where_is_my_friends_notify_city: this.notifyCity,
        },
      });
    } catch {
      this.notifyCity = !this.notifyCity;
    }
  }

  @action
  toggleJoinNotifyCity() {
    this.notifyCity = !this.notifyCity;
  }

  @action
  toggleJoinNotifyNearby() {
    this.notifyNearby = !this.notifyNearby;
  }

  errorMessage(error) {
    const response = error?.jqXHR?.responseJSON ?? error?.responseJSON;
    return response?.errors?.[0] ?? i18n("where_is_my_friends.generic_error");
  }

  <template>
    <main
      class="where-is-my-friends"
      data-state={{this.discoveryState}}
      {{didInsert this.initialize}}
    >
      <header class="where-is-my-friends__header">
        <p class="where-is-my-friends__eyebrow">{{i18n
            "where_is_my_friends.eyebrow"
          }}</p>
        <h1>{{i18n "where_is_my_friends.title"}}</h1>
        <p>{{i18n "where_is_my_friends.description"}}</p>
      </header>

      {{#if this.error}}
        <div class="alert alert-error" data-test-error>{{this.error}}</div>
      {{/if}}

      {{#if this.isSetup}}
        <WhereIsMyFriendsSetupPanel
          @autoCity={{this.autoCity}}
          @city={{this.city}}
          @cityDirectory={{this.cityDirectory}}
          @cityNormalizationHint={{this.cityNormalizationHint}}
          @cityOptions={{this.cityOptions}}
          @cityPreview={{this.cityPreview}}
          @hasCityDirectory={{this.hasCityDirectory}}
          @loading={{this.loading}}
          @networkPreview={{this.networkPreview}}
          @notifyCity={{this.notifyCity}}
          @notifyNearby={{this.notifyNearby}}
          @participantProof={{this.participantProof}}
          @previewCurrentCity={{this.previewCurrentCity}}
          @previewJoinLabel={{this.previewJoinLabel}}
          @previewLoading={{this.previewLoading}}
          @previewRadiusButtons={{this.previewRadiusButtons}}
          @previewSuggestedCity={{this.previewSuggestedCity}}
          @region={{this.region}}
          @revealRegion={{this.revealRegion}}
          @saveCity={{this.saveCity}}
          @selectPreviewRadius={{this.selectPreviewRadius}}
          @showRegion={{this.showRegion}}
          @toggleJoinNotifyCity={{this.toggleJoinNotifyCity}}
          @toggleJoinNotifyNearby={{this.toggleJoinNotifyNearby}}
          @trackLocalTopicCompose={{this.trackLocalTopicCompose}}
          @updateCity={{this.updateCity}}
          @updateRegion={{this.updateRegion}}
        />
      {{else}}
        <WhereIsMyFriendsResultsPanel
          @model={{@model}}
          @chatEnabled={{this.chatEnabled}}
          @copyInvite={{this.copyInvite}}
          @discoveryRadiusButtons={{this.discoveryRadiusButtons}}
          @displayCityGroups={{this.displayCityGroups}}
          @editLocation={{this.editLocation}}
          @expandedRadius={{this.expandedRadius}}
          @expandedRadiusKm={{this.expandedRadiusKm}}
          @filterGroups={{this.filterGroups}}
          @gpsFallback={{this.gpsFallback}}
          @hasActiveFilters={{this.hasActiveFilters}}
          @hasFilterableFields={{this.hasFilterableFields}}
          @hasUsers={{this.hasUsers}}
          @inviteFeedback={{this.inviteFeedback}}
          @isEmpty={{this.isEmpty}}
          @loading={{this.loading}}
          @localTopicActionUrl={{this.localTopicActionUrl}}
          @location={{this.location}}
          @memberFilter={{this.memberFilter}}
          @nearbyCityCount={{this.nearbyCityCount}}
          @notifyCity={{this.notifyCity}}
          @openAdvancedLocation={{this.openAdvancedLocation}}
          @originalRadiusKm={{this.originalRadiusKm}}
          @participantProof={{this.participantProof}}
          @removeLocation={{this.removeLocation}}
          @resultsSummary={{this.resultsSummary}}
          @selectDiscoveryRadius={{this.selectDiscoveryRadius}}
          @selectFilter={{this.selectFilter}}
          @showMemberFilter={{this.showMemberFilter}}
          @toggleNotifyCity={{this.toggleNotifyCity}}
          @trackConnection={{this.trackConnection}}
          @trackLocalTopicOpen={{this.trackLocalTopicOpen}}
          @updateMemberFilter={{this.updateMemberFilter}}
        />
      {{/if}}
    </main>
  </template>
}
