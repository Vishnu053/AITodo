<template>
  <q-page>
       <q-editor v-model="card.content" min-height="6rem" />
  </q-page>
</template>

<script>
export default {
  data () {
    return {
      card: {}
    }
  },
  mounted () {
    this.card = JSON.parse(localStorage.getItem('tmpnt'))
    // localStorage.removeItem('tmpnt')
  }
}
</script>
