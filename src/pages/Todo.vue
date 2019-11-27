<template>
  <q-page>
        <q-header elevated>
      <div class="q-px-lg q-pt-xl q-mb-md">
        <div class="text-h4 q-pb-lg q-pt-sm">Hi {{user.name}}!</div>
        <div class="text-subtitle">{{dt}}</div>
      </div>
       <div style="width:100%;text-align:center;" class="q-pa-sm">
         <q-btn round outline color="white" @click="newNote"><q-icon name="add"></q-icon></q-btn>
         </div>
      <q-img src="https://source.unsplash.com/random" class="header-image absolute-top headr-blr"></q-img>
    </q-header>
    <div :style="'overflow: hidden auto; max-height:'+whgt+'px;'">
      <div>
        <!-- <div class="col-12 blur-bg q-banner--dense text-subtitle1 text-white" style="background:radial-gradient(circle, rgba(255, 255, 255, 0.55) 0%, rgba(49, 49, 49, 0.28) 100%);">Recent</div> -->
        <div class="">
      <q-card clickable v-ripple v-for="(card,index) in cards" v-bind:key="index"
        class="my-card text-white col-12 blur-bg q-ma-sm"
        style="background: radial-gradient(circle, rgba(165, 165, 165, 0.68) 0%, rgba(0, 0, 0, 0.28) 100%)"
        @click="openNote(card)"
      >
        <q-card-section>
          <div class="text-h6 q-pb-md q-pt-sm">{{card.title}}</div>
          <!-- <div class="text-subtitle2">by {{card.author}}</div> -->
        </q-card-section>
      </q-card>
      </div>
    </div>
    </div>
    <q-img src="https://source.unsplash.com/random" class="header-image absolute-top "></q-img>
  </q-page>
</template>

<script>
import { date } from 'quasar'
export default {
  data () {
    return {
      whgt: window.innerHeight - 168,
      user: {
        name: 'Vishnu'
      },
      dt: '',
      cards: []
    }
  },
  mounted () {
    let timeStamp = Date.now()
    this.dt = date.formatDate(timeStamp, 'dddd, MMMM DD')
    this.getNotes()
    // var a = [{ id: 'tdx-nt-1', title: 'As I Dream', content: 'Lorem ipsum dolor sit amet consectetur adipisicing elit. Ut.' }, { id: 'tdx-nt-1', title: 'As I Dream 2', content: 'Lorem ipsum dolor sit amet consectetur adipisicing elit. Ut.' }]
    // localStorage.setItem('AITDnotes', JSON.stringify(a))
  },
  methods: {
    getNotes () {
      this.cards = JSON.parse(localStorage.getItem('AITDnotes'))
      // console.log(this.cards)
    },
    newNote () {
      var an = JSON.parse(localStorage.getItem('AITDnotes'))
      if (an == null) {
        var tnn = { id: 'tdx-nt-1', title: 'My Title', content: 'Lorem ipsum...' }
        this.openNote(tnn)
      } else {
        var anc = 'tdx-nt-' + parseInt(an.length + 1)
        var tn = { id: anc, title: 'My Title', content: 'Lorem ipsum...' }
        this.openNote(tn)
      }
    },
    openNote (note) {
      localStorage.setItem('tmpnt', JSON.stringify(note))
      this.$router.push('/note')
    }
  }
}
</script>
