<template>
  <q-page style="background:#fafafa;">
    <div class="col-12 q-pl-md q-pr-md bold-input" style="background:#e2e2e2;">
    <q-input small borderless placeholder="Enter Title..." v-model="card.title"></q-input>
    </div>
    <div v-if="card.content && showEditor">
       <q-editor v-model="card.content" :min-height="whgt" style="background:#fff0;" class="custom-editor"/>
       <div style="width:100%;text-align:right;" class="q-pa-sm">
         <q-btn round outline color="primary" @click="updateDt"><q-icon name="check"></q-icon></q-btn>
         </div>
         </div>
  </q-page>
</template>

<script>
export default {
  data () {
    return {
      whgt: '8rem',
      showEditor: false,
      card: {}
    }
  },
  mounted () {
    this.card = JSON.parse(localStorage.getItem('tmpnt'))
    // localStorage.removeItem('tmpnt')
    this.whgt = (window.innerHeight - 168).toString() + 'px'
    this.showEditor = true
  },
  methods: {
    updateDt () {
      console.log(this.card)
    }
  }
}
</script>
