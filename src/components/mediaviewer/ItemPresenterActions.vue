<template>
  <!-- eslint-disable @intlify/vue-i18n/no-raw-text -->
  <q-page-sticky position="bottom" class="q-ma-lg">
    <div class="q-mb-lg action-buttons row flex flex-center">
      <q-btn
        stack
        rounded
        class="q-mr-lg action-button col-auto glass-effect"
        color="negative"
        no-caps
        icon="sym_o_cancel"
        label="Annuler cette prise"
        :disable="isBusy"
        @click="abortCapture"
      />
      <q-btn
        stack
        rounded
        class="q-mr-lg action-button col-auto glass-effect"
        color="primary"
        no-caps
        icon="sym_o_replay"
        label="Recommencer"
        :disable="isBusy"
        @click="rejectCapture"
      />
      <q-btn
        stack
        rounded
        class="q-mr-sm action-button col-auto glass-effect"
        color="positive"
        no-caps
        icon="sym_o_thumb_up"
        label="Valider ma photo"
        :loading="isConfirming"
        :disable="isBusy"
        @click="confirmCapture"
      />
    </div>
  </q-page-sticky>

  <div v-if="showQrOverlay" class="photoo-event-qr-overlay">
    <section class="photoo-event-qr-panel">
      <h1>Récupérez votre photo</h1>
      <p class="photoo-event-qr-subtitle">Scannez ce QR code avec votre téléphone.</p>
      <div class="photoo-event-qr-code">
        <qrcode-vue :value="shareUrl" :margin="2" :size="480" level="L" render-as="svg" />
      </div>
      <p class="photoo-event-qr-secondary">Votre photo est disponible pendant quelques jours.</p>
      <p class="photoo-event-qr-countdown">Retour à l’accueil dans {{ countdown }} secondes</p>
    </section>
  </div>
</template>

<script setup lang="ts">
import { computed, onBeforeUnmount, ref } from 'vue'
import { useQuasar } from 'quasar'
import { useRouter } from 'vue-router'
import QrcodeVue from 'qrcode.vue'
import { _fetch } from 'src/util/fetch_api'
import { useConfigurationStore } from 'src/stores/configuration-store'
import { useStateStore } from 'src/stores/state-store'

const props = defineProps<{
  mediaitemId: string
  mediaType: string
}>()

const $q = useQuasar()
const router = useRouter()
const configurationStore = useConfigurationStore()
const stateStore = useStateStore()
const isConfirming = ref(false)
const isNavigating = ref(false)
const showQrOverlay = ref(false)
const shareUrl = ref('')
const countdown = ref(25)
let countdownTimer: number | undefined

const isBusy = computed(() => isConfirming.value || isNavigating.value || showQrOverlay.value)

function clearCountdown() {
  if (countdownTimer) {
    window.clearInterval(countdownTimer)
    countdownTimer = undefined
  }
}

function returnHome() {
  clearCountdown()
  showQrOverlay.value = false
  void router.push({ path: '/' })
}

async function sendAction(url: string) {
  const response = await _fetch(url)
  if (!response.ok) {
    throw new Error(`Request failed: ${response.status} ${response.statusText}`)
  }
}

function normalizeForComparison(value: unknown) {
  return JSON.stringify(value)
}

function resolveAction() {
  const actionType =
    stateStore.jobmodel.present_mediaitem_id === props.mediaitemId && stateStore.jobmodel.typ ? stateStore.jobmodel.typ : props.mediaType

  if (!['image', 'collage'].includes(actionType)) {
    throw new Error(`Unsupported action type for retry: ${actionType}`)
  }

  const actions = configurationStore.configuration.actions[actionType]
  if (!Array.isArray(actions) || actions.length === 0) {
    throw new Error(`No configured action found for type: ${actionType}`)
  }

  const lastConfigurationSet = stateStore.jobmodel.present_mediaitem_id === props.mediaitemId ? stateStore.jobmodel.configuration_set : null
  const actionIndex = lastConfigurationSet
    ? actions.findIndex((action) => normalizeForComparison(action) === normalizeForComparison(lastConfigurationSet))
    : actions.length === 1
      ? 0
      : -1

  if (actionIndex < 0) {
    throw new Error(`Cannot identify the source action for this ${actionType}.`)
  }

  return { actionType, actionIndex }
}

async function abortCapture() {
  if (isBusy.value) {
    return
  }

  returnHome()
}

async function rejectCapture() {
  if (isBusy.value) {
    return
  }

  isNavigating.value = true
  try {
    clearCountdown()
    showQrOverlay.value = false
    const { actionType, actionIndex } = resolveAction()
    await sendAction(`/api/actions/${actionType}/${actionIndex}`)
    returnHome()
  } catch (error) {
    isNavigating.value = false
    notifyError(error)
  }
}

async function confirmCapture() {
  if (isBusy.value) {
    return
  }

  isConfirming.value = true
  try {
    const url = await getShareUrl(props.mediaitemId)
    shareUrl.value = url
    showQrOverlay.value = true
    startCountdown()
  } catch (error) {
    notifyError(error)
  } finally {
    isConfirming.value = false
  }
}

async function getShareUrl(mediaitemId: string) {
  const response = await _fetch(`/api/share/download/${mediaitemId}`)
  if (!response.ok) {
    throw new Error(`Share URL request failed: ${response.status} ${response.statusText}`)
  }

  const urls = await response.json()
  if (!Array.isArray(urls) || typeof urls[0] !== 'string' || urls[0].length === 0) {
    throw new Error('No share URL returned for this media item.')
  }

  return urls[0]
}

function startCountdown() {
  clearCountdown()
  countdown.value = 25
  countdownTimer = window.setInterval(() => {
    countdown.value -= 1
    if (countdown.value <= 0) {
      returnHome()
    }
  }, 1000)
}

function notifyError(error: unknown) {
  console.error(error)
  $q.notify({
    message: String(error),
    caption: 'Request Error!',
    color: 'negative',
  })
}

onBeforeUnmount(() => {
  clearCountdown()
})
</script>

<style lang="sass" scoped>
.photoo-event-qr-overlay
  position: fixed
  inset: 0
  z-index: 2147483647
  display: flex
  align-items: center
  justify-content: center
  padding: clamp(24px, 4vw, 64px)
  background: #101214
  color: #fff
  text-align: center

.photoo-event-qr-panel
  display: flex
  flex-direction: column
  align-items: center
  gap: clamp(16px, 2.5vh, 30px)
  width: min(92vw, 880px)

  h1
    margin: 0
    font-size: clamp(44px, 6vw, 88px)
    line-height: 1.04
    font-weight: 850

.photoo-event-qr-subtitle
  margin: 0
  font-size: clamp(24px, 3vw, 42px)
  line-height: 1.2
  color: #f2f2f2

.photoo-event-qr-code
  width: min(54vh, 58vw, 520px)
  aspect-ratio: 1
  padding: clamp(14px, 2vw, 24px)
  background: #fff
  border-radius: 8px
  box-shadow: 0 22px 70px rgba(0, 0, 0, 0.34)

  svg
    display: block
    width: 100%
    height: 100%

.photoo-event-qr-secondary,
.photoo-event-qr-countdown
  margin: 0
  font-size: clamp(18px, 2vw, 30px)

.photoo-event-qr-secondary
  color: #d7d7d7

@media (max-width: 720px)
  .photoo-event-qr-overlay
    padding: 18px

  .photoo-event-qr-code
    width: min(72vw, 420px)
</style>
