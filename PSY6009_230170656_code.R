set.seed(123)

#clean environment
rm(list=ls())

#packages
#libraries<-c("here", "tidyverse", "lmerTest", "lavaan", "semTools", "purrr", "tidymodels", "semPlot", "finalfit", "GGally", "car", "bestNormalize", "performance")
#install.packages(libraries, repos="http://cran.rstudio.com")

library(here)
library(tidyverse)
library(lmerTest)
library(ggplot2)
library(gridExtra)
library(purrr)
library(tidyr)
library(MuMIn)
library(finalfit)
library(GGally)
library(car)
library(performance)

################################################################################
################################ RAW DATA ######################################
################################################################################

#demographic data & attrition
home_survey<-read.csv(here("raw_data","survey_home.csv"))
lab_survey<-read.csv(here("raw_data","survey_lab.csv"))
filter<-read.csv(here("raw_data","tracker_inclusions.csv"))

#training and near transfer
simple_data<-read.csv(here("raw_data","assessment_training_simple.csv"))
choice_data<-read.csv(here("raw_data","assessment_training_choice.csv"))
switch_data<-read.csv(here("raw_data","assessment_training_switch.csv"))
dual_data<-read.csv(here("raw_data","assessment_training_dual.csv"))

#far transfer
wm_updating<-read.csv(here("raw_data","assessment_wm_updating.csv"))
wm_binding<-read.csv(here("raw_data","assessment_wm_binding.csv"))
wm_reproduction<-read.csv(here("raw_data","assessment_wm_reproduction.csv"))
reas_rapm<-read.csv(here("raw_data","assessment_reas_rapm.csv"))
reas_lettersets<-read.csv(here("raw_data","assessment_reas_lettersets.csv"))
reas_paperfolding<-read.csv(here("raw_data","assessment_reas_paperfolding.csv"))

################################################################################
############################### PROCESSING #####################################
################################################################################

# cognition-related beliefs ######################################################################################################################################

sex_age_grit<-home_survey %>%
  select(code,group,site,demo.sex,demo.age.years,demo.age.group,demo.gender,grit)

gse_tis<-lab_survey %>%
  select(code,sessionId,gse,tis) %>%
  filter(sessionId==1) #only session 1 used; idea of CRB as stable

crb<-inner_join(sex_age_grit,
                gse_tis %>% select(code,gse,tis),by="code")

######### training and near transfer ######################################

process<-function(data, suffix) {data %>%
    select(code,assessment,material,speed) %>%
    spread(key=material, value=speed) %>%
    rename(sessionId=assessment,
           !!paste0(suffix, "_draw_rt"):=drawings,
           !!paste0(suffix, "_numb_rt"):=numbers,
           !!paste0(suffix, "_shap_rt"):=shapes)}

simple_rt<-process(simple_data, "simp")
choice_rt<-process(choice_data, "choi")
switch_data<-switch_data %>% rename(speed=speed.switch)
switch_rt<-process(switch_data, "swit")

dual_data$speed<-pmax(dual_data$speed.response1,dual_data$speed.response2) #slower RT preferenced
dual_rt<-process(dual_data, "dual")

# far transfer #####################################################################################################################################################

f_t_dfs<-list(reas_ls=reas_lettersets,reas_pf=reas_paperfolding,reas_ra=reas_rapm,
              work_bi=wm_binding,work_re=wm_reproduction,work_up=wm_updating)

f_t_outcomes<-list(reas_ls="assessment.reas.lettersets.score",
                   reas_pf="assessment.reas.paperfolding.score",
                   reas_ra="assessment.reas.rapm.score",
                   work_bi="wm.binding.dprime",
                   work_re="wm.reproduction.error",
                   work_up="wm.updating.accuracy")

process2<-function(data, f_t_outcome) {data %>%
    select(code,assessment,!!sym(f_t_outcome)) %>%
    rename(sessionId=assessment)}

processed_ft<-map2(f_t_dfs, f_t_outcomes, process2)
names(processed_ft)<-names(f_t_dfs)
reas_ls<-processed_ft$reas_ls
reas_pf<-processed_ft$reas_pf
reas_ra<-processed_ft$reas_ra
work_bi<-processed_ft$work_bi
work_re<-processed_ft$work_re
work_up<-processed_ft$work_up

# cognition-related beliefs, skill enhancement and near/far transfer ###############################################################################################
raw_data<-crb %>%
  full_join(simple_rt, by=c("code")) %>%
  full_join(choice_rt, by=c("code","sessionId")) %>%
  full_join(switch_rt, by=c("code","sessionId")) %>%
  full_join(dual_rt, by=c("code","sessionId")) %>%
  full_join(reas_ls, by=c("code","sessionId")) %>%
  full_join(reas_pf, by=c("code","sessionId")) %>%
  full_join(reas_ra, by=c("code","sessionId")) %>%
  full_join(work_bi, by=c("code","sessionId")) %>%
  full_join(work_up, by=c("code","sessionId")) %>%
  full_join(work_re, by=c("code","sessionId"))

raw_data%>%
  count(sessionId) #422 pretest, 398 posttest, 388 follow-up

#create filter
inclusions<-filter$code[filter$t6Complete == "Y"]

processed_data<-raw_data %>%
  filter(code %in% inclusions)

processed_data$sessionId=recode(processed_data$sessionId, "'follow-up'='followup'") 

#check for missing data
table(is.na(processed_data)) #229 values missing
pps_missing_data<-unique(processed_data$code[!complete.cases(processed_data)]) #32 participants have missing values

processed_data %>%
  missing_plot() + labs(x = "Observation", y = "Variable", title = "Missingness Plot for Necessary Variables") + theme(plot.title = element_text(hjust = 0.5, size = 16, face = "bold")) +
  scale_y_discrete(labels=c("Working Memory: reproduction error","Working Memory: updating accuracy","Working Memory: discrimination parameter","Reasoning: matrix reasoning",
                            "Reasoning: paperfolding","Reasoning: lettersets","Dual: shapes","Dual: numbers","Dual: drawings","Switching: shapes","Switching: numbers","Switching: drawings",
                            "Choice: shapes","Choice: numbers","Choice: drawings","Simple: shapes","Simple: numbers","Simple: drawings","Assessment Time-Point","Mindset","Self-Efficacy",
                            "Grit","Gender","Age-group","Age","Sex","Cognitive Site","Training Group","Participant Code")) #visually, missingness is limited to a small amount of participants and does not appear to be systematic
 
processed_data<-processed_data[!processed_data$code %in% pps_missing_data, ] #removed all data for those with missing values

#additional check for missing sessions for each participant
processed_data%>% count(sessionId) #1 participant missing session 3
#identifies and removes all data for this participant
sessions<-processed_data %>%
  group_by(code) %>%
  summarise(session_count=n_distinct(sessionId))
complete<-sessions %>%
  filter(session_count==3) %>%
  pull(code)
processed_data<-processed_data %>%
  filter(code %in% complete) #356 remaining participants

processed_data%>% count(sessionId)
rm(list=setdiff(ls(), c("processed_data","crb")))
processed_data%>% count(group) #95 simple, 89 choice, 88 switch, 84 dual

#final demographic data
mean((processed_data$demo.age.years))# 48.62
range((processed_data$demo.age.years))# 18-85
sd((processed_data$demo.age.years))# 18.13
processed_data%>%
  count(demo.age.group) # 146 middle-aged, 80 older, 130 younger
processed_data%>%
  count(demo.gender) # 155 male, 200 female, 1 prefer not to say
processed_data%>%
  count(site) # 115 Hamburg, 116 Montreal, 125 Sheffield

###################### analysis preparation ########################################################################

########################################################## SIMPLE #####################################################################

simp_outcome<-processed_data %>%
  select(code,site,group,sessionId,demo.age.years,grit,tis,gse,simp_draw_rt,simp_numb_rt,simp_shap_rt) %>%
  pivot_longer(cols=ends_with("_rt"),
               names_to="material",
               values_to="_rt") %>%
  pivot_wider(names_from=sessionId, values_from=`_rt`)

simp_outcome$group <- factor(simp_outcome$group, ordered=FALSE)
simp_outcome$group <- relevel(simp_outcome$group, ref="Simple")

lmer_simp_b<-lmer(pretest~group+(1|site)+(1|code)+(1|material)+demo.age.years+grit*group+gse*group+tis*group,data=simp_outcome)
lmer_simp_e<-lmer(posttest~group*pretest+(1|site)+(1|code)+(1|material)+demo.age.years+grit*group+gse*group+tis*group,data=simp_outcome)
lmer_simp_m<-lmer(followup~group*posttest+(1|site)+(1|code)+(1|material)+demo.age.years+grit*group+gse*group+tis*group,data=simp_outcome)

#checks

#normality of residual distribution
qqnorm(resid(lmer_simp_b))
qqnorm(resid(lmer_simp_e))
qqnorm(resid(lmer_simp_m))

#homoscedasticity of variance and linearity of model relationships
plot(lmer_simp_b)
plot(lmer_simp_e)
plot(lmer_simp_m)

#remove >=200ms RTs and 3MAD+median< RTs
pps_exclude1<-simp_outcome%>%
  group_by(code) %>%
  filter(any(pretest < 200)) %>%
  filter(any(posttest < 200)) %>%
  filter(any(followup < 200)) %>%
  pull(code) %>% unique() #none

medianRT1<-median(simp_outcome$pretest)
MAD_3_RT1<-3*mad(simp_outcome$pretest)
medianRT2<-median(simp_outcome$posttest)
MAD_3_RT2<-3*mad(simp_outcome$posttest)
medianRT3<-median(simp_outcome$followup)
MAD_3_RT3<-3*mad(simp_outcome$followup)

pps_exclude2<-simp_outcome%>%
  group_by(code) %>%
  filter(pretest > (medianRT1+MAD_3_RT1)) %>%
  filter(posttest > (medianRT2+MAD_3_RT2)) %>%
  filter(followup > (medianRT3+MAD_3_RT3)) %>%
  pull(code) %>% unique() #4 extreme Ids

extremes<-union(pps_exclude1,pps_exclude2) #4 extreme Ids
simp_outcome<-simp_outcome %>%
  filter(!simp_outcome$code %in% extremes) #removes all data for extreme pps (-12 observations)

#transformation
simp_outcome$pretest<-log(simp_outcome$pretest)
simp_outcome$posttest<-log(simp_outcome$posttest)
simp_outcome$followup<-log(simp_outcome$followup)

#re-run lines 208-210

#singularity issue for maintenance model
print(summary(lmer_simp_m),cor=F) #site variance negligible - removed
lmer_simp_m<-lmer(followup~group*posttest+(1|code)+(1|material)+demo.age.years+grit*group+gse*group+tis*group,data=simp_outcome)

#cooks distance check
cooksD<-cooks.distance(lmer_simp_b)
influential1<-simp_outcome$code[which(cooksD>1)]
cooksD<-cooks.distance(lmer_simp_e)
influential2<-simp_outcome$code[which(cooksD>1)]
cooksD<-cooks.distance(lmer_simp_m)
influential3<-simp_outcome$code[which(cooksD>1)]
influential<-union(influential1,influential2)
influential<-union(influential,influential3) #12 influential outlying observations; 7 pps
simp_outcome<-simp_outcome[!simp_outcome$code %in% influential, ] #removes all data for extreme pps (-21 observations) (1035 in total)

#z-standardise
simp_outcome$demo.age.years<-scale(simp_outcome$demo.age.years)
simp_outcome$grit<-scale(simp_outcome$grit)
simp_outcome$tis<-scale(simp_outcome$tis)
simp_outcome$gse<-scale(simp_outcome$gse)
simp_outcome$pretest<-scale(simp_outcome$pretest)
simp_outcome$posttest<-scale(simp_outcome$posttest)
simp_outcome$followup<-scale(simp_outcome$followup)

#re-run lines 208-209, 259

#lack of perfect multicolinearity
multicolinearity_test<-vif(lmer_simp_b, type="predictor") #grit (2.1), gse (2)
multicolinearity_test<-vif(lmer_simp_e, type="predictor") #pretest (2.1), grit (2.2), gse (2)
multicolinearity_test<-vif(lmer_simp_m, type="predictor") #posttest (2.4), grit (2.2), gse (2.1)

#final models
lmer_simp_b<-lmer(pretest~group+(1|site)+(1|code)+(1|material)+demo.age.years+grit*group+gse*group+tis*group,data=simp_outcome)
lmer_simp_e<-lmer(posttest~group*pretest+(1|site)+(1|code)+(1|material)+demo.age.years+grit*group+gse*group+tis*group,data=simp_outcome)
lmer_simp_m<-lmer(followup~group*posttest+(1|code)+(1|material)+demo.age.years+grit*group+gse*group+tis*group,data=simp_outcome)

print(summary(lmer_simp_b),cor=F)
print(summary(lmer_simp_e),cor=F)
print(summary(lmer_simp_m),cor=F)

########################################################## CHOICE #####################################################################

choi_outcome<-processed_data %>%
  select(code,site,group,sessionId,demo.age.years,grit,tis,gse,choi_draw_rt,choi_numb_rt,choi_shap_rt) %>%
  pivot_longer(cols=ends_with("_rt"),
               names_to="material",
               values_to="_rt") %>%
  pivot_wider(names_from=sessionId, values_from=`_rt`)

choi_outcome$group <- factor(choi_outcome$group, ordered=FALSE)
choi_outcome$group <- relevel(choi_outcome$group, ref="Simple")

lmer_choi_b<-lmer(pretest~group+(1|site)+(1|code)+(1|material)+demo.age.years+grit*group+gse*group+tis*group,data=choi_outcome)
lmer_choi_e<-lmer(posttest~group*pretest+(1|site)+(1|code)+(1|material)+demo.age.years+grit*group+gse*group+tis*group,data=choi_outcome)
lmer_choi_m<-lmer(followup~group*posttest+(1|site)+(1|code)+(1|material)+demo.age.years+grit*group+gse*group+tis*group,data=choi_outcome)

#singularity issue with baseline model
isSingular(lmer_choi_b) #true
print(summary(lmer_choi_b),cor=F) #site variance negligible - removed
lmer_choi_b<-lmer(pretest~group+(1|code)+(1|material)+demo.age.years+grit*group+gse*group+tis*group,data=choi_outcome)

#checks

#normality of residual distribution
qqnorm(resid(lmer_choi_b))
qqnorm(resid(lmer_choi_e))
qqnorm(resid(lmer_choi_m))

#homoscedasticity of variance and linearity of model relationships
plot(lmer_choi_b)
plot(lmer_choi_e)
plot(lmer_choi_m)

#remove >=200ms RTs and 3MAD+median< RTs
pps_exclude1<-choi_outcome%>%
  group_by(code) %>%
  filter(any(pretest < 200)) %>%
  filter(any(posttest < 200)) %>%
  filter(any(followup < 200)) %>%
  pull(code) %>% unique() #none

medianRT1<-median(choi_outcome$pretest)
MAD_3_RT1<-3*mad(choi_outcome$pretest)
medianRT2<-median(choi_outcome$posttest)
MAD_3_RT2<-3*mad(choi_outcome$posttest)
medianRT3<-median(choi_outcome$followup)
MAD_3_RT3<-3*mad(choi_outcome$followup)

pps_exclude2<-choi_outcome%>%
  group_by(code) %>%
  filter(pretest > (medianRT1+MAD_3_RT1)) %>%
  filter(posttest > (medianRT2+MAD_3_RT2)) %>%
  filter(followup > (medianRT3+MAD_3_RT3)) %>%
  pull(code) %>% unique() #5 extreme Ids

extremes<-union(pps_exclude1,pps_exclude2) #5 extreme Ids
choi_outcome<-choi_outcome %>%
  filter(!choi_outcome$code %in% extremes) #removes all data for extreme pps (-15 observations)

#transformation
choi_outcome$pretest<-log(choi_outcome$pretest)
choi_outcome$posttest<-log(choi_outcome$posttest)
choi_outcome$followup<-log(choi_outcome$followup)

#re-run lines 310-311 and 316

#cooks distance method
cooksD<-cooks.distance(lmer_choi_b)
influential1<-choi_outcome$code[which(cooksD>1)]
cooksD<-cooks.distance(lmer_choi_e)
influential2<-choi_outcome$code[which(cooksD>1)]
cooksD<-cooks.distance(lmer_choi_m)
influential3<-choi_outcome$code[which(cooksD>1)]
influential<-union(influential1,influential2)
influential<-union(influential,influential3) #6 influential outlying observations; 3 pps
choi_outcome<-choi_outcome[!choi_outcome$code %in% influential, ] #removes all data for extreme pps (-9 observations) (1044 in total)

#z-standardise
choi_outcome$demo.age.years<-scale(choi_outcome$demo.age.years)
choi_outcome$grit<-scale(choi_outcome$grit)
choi_outcome$tis<-scale(choi_outcome$tis)
choi_outcome$gse<-scale(choi_outcome$gse)
choi_outcome$pretest<-scale(choi_outcome$pretest)
choi_outcome$posttest<-scale(choi_outcome$posttest)
choi_outcome$followup<-scale(choi_outcome$followup)

#re-run lines 310-311 and 316

#lack of perfect multicolinearity
multicolinearity_test<-vif(lmer_choi_b, type="predictor") #grit (2.3), gse (2.2)
multicolinearity_test<-vif(lmer_choi_e, type="predictor") #grit (2.3), gse (2.1)
multicolinearity_test<-vif(lmer_choi_m, type="predictor") #grit (2.3), gse (2.2)

#final models
lmer_choi_b<-lmer(pretest~group+(1|code)+(1|material)+demo.age.years+grit*group+gse*group+tis*group,data=choi_outcome)
lmer_choi_e<-lmer(posttest~group*pretest+(1|site)+(1|code)+(1|material)+demo.age.years+grit*group+gse*group+tis*group,data=choi_outcome)
lmer_choi_m<-lmer(followup~group*posttest+(1|site)+(1|code)+(1|material)+demo.age.years+grit*group+gse*group+tis*group,data=choi_outcome)

print(summary(lmer_choi_b),cor=F)
print(summary(lmer_choi_e),cor=F)
print(summary(lmer_choi_m),cor=F)

########################################################## SWITCH #####################################################################

swit_outcome<-processed_data %>%
  select(code,site,group,sessionId,demo.age.years,grit,tis,gse,swit_draw_rt,swit_numb_rt,swit_shap_rt) %>%
  pivot_longer(cols=ends_with("_rt"),
               names_to="material",
               values_to="_rt") %>%
  pivot_wider(names_from=sessionId, values_from=`_rt`)

swit_outcome$group <- factor(swit_outcome$group, ordered=FALSE)
swit_outcome$group <- relevel(swit_outcome$group, ref="Simple")

lmer_swit_b<-lmer(pretest~group+(1|site)+(1|code)+(1|material)+demo.age.years+grit*group+gse*group+tis*group,data=swit_outcome)
lmer_swit_e<-lmer(posttest~group*pretest+(1|site)+(1|code)+(1|material)+demo.age.years+grit*group+gse*group+tis*group,data=swit_outcome)
lmer_swit_m<-lmer(followup~group*posttest+(1|site)+(1|code)+(1|material)+demo.age.years+grit*group+gse*group+tis*group,data=swit_outcome) 

#singularity issue with baseline and enhancement model
isSingular(lmer_swit_b) #true
isSingular(lmer_swit_e) #true
print(summary(lmer_swit_b),cor=F) #site explains no variance, #respectification below
print(summary(lmer_swit_e),cor=F) #site explains no variance, #respectification below
lmer_swit_b<-lmer(pretest~group+(1|code)+(1|material)+demo.age.years+grit*group+gse*group+tis*group,data=swit_outcome)
lmer_swit_e<-lmer(posttest~group*pretest+(1|code)+(1|material)+demo.age.years+grit*group+gse*group+tis*group,data=swit_outcome)

#checks

#normality of residual distribution
qqnorm(resid(lmer_swit_b))
qqnorm(resid(lmer_swit_e))
qqnorm(resid(lmer_swit_m))

#homoscedasticity of variance and linearity of model relationships
plot(lmer_swit_b)
plot(lmer_swit_e)
plot(lmer_swit_m)

#remove >=200ms RTs and 3MAD+median< RTs
pps_exclude1<-swit_outcome%>%
  group_by(code) %>%
  filter(any(pretest < 200)) %>%
  filter(any(posttest < 200)) %>%
  filter(any(followup < 200)) %>%
  pull(code) %>% unique() #2 extreme Ids

medianRT1<-median(swit_outcome$pretest)
MAD_3_RT1<-3*mad(swit_outcome$pretest)
medianRT2<-median(swit_outcome$posttest)
MAD_3_RT2<-3*mad(swit_outcome$posttest)
medianRT3<-median(swit_outcome$followup)
MAD_3_RT3<-3*mad(swit_outcome$followup)

pps_exclude2<-swit_outcome%>%
  group_by(code) %>%
  filter(pretest > (medianRT1+MAD_3_RT1)) %>%
  filter(posttest > (medianRT2+MAD_3_RT2)) %>%
  filter(followup > (medianRT3+MAD_3_RT3)) %>%
  pull(code) %>% unique() #3 extreme Ids

extremes<-union(pps_exclude1,pps_exclude2) #5 extreme Ids
swit_outcome<-swit_outcome %>%
  filter(!swit_outcome$code %in% extremes) #removes all data for extreme pps (-15 observations)

#transformation
swit_outcome$pretest<-log(swit_outcome$pretest)
swit_outcome$posttest<-log(swit_outcome$posttest)
swit_outcome$followup<-log(swit_outcome$followup)

#re-run lines 413, 420-421

#cooks distance method
cooksD<-cooks.distance(lmer_swit_b)
influential1<-swit_outcome$code[which(cooksD>1)]
cooksD<-cooks.distance(lmer_swit_e)
influential2<-swit_outcome$code[which(cooksD>1)]
cooksD<-cooks.distance(lmer_swit_m)
influential3<-swit_outcome$code[which(cooksD>1)]
influential<-union(influential1,influential2)
influential<-union(influential,influential3) #11 influential outlying observations; 5 pps
swit_outcome<-swit_outcome[!swit_outcome$code %in% influential, ] #removes all data for extreme pps (-15 observations) (1038 in total)

#z-standardise
swit_outcome$demo.age.years<-scale(swit_outcome$demo.age.years)
swit_outcome$grit<-scale(swit_outcome$grit)
swit_outcome$tis<-scale(swit_outcome$tis)
swit_outcome$gse<-scale(swit_outcome$gse)
swit_outcome$pretest<-scale(swit_outcome$pretest)
swit_outcome$posttest<-scale(swit_outcome$posttest)
swit_outcome$followup<-scale(swit_outcome$followup)

#re-run lines 413, 420-421

#lack of perfect multicolinearity
multicolinearity_test<-vif(lmer_swit_b, type="predictor") #grit (2.3), gse (2.2)
multicolinearity_test<-vif(lmer_swit_e, type="predictor") #grit (2.3), gse (2.2)
multicolinearity_test<-vif(lmer_swit_m, type="predictor") #posttest (2.2), grit (2.3), gse (2.2)

#final models: (1|site) re-included as singularities resolved following outlier removal
lmer_swit_b<-lmer(pretest~group+(1|site)+(1|code)+(1|material)+demo.age.years+grit*group+gse*group+tis*group,data=swit_outcome)
lmer_swit_e<-lmer(posttest~group*pretest+(1|site)+(1|code)+(1|material)+demo.age.years+grit*group+gse*group+tis*group,data=swit_outcome)
lmer_swit_m<-lmer(followup~group*posttest+(1|site)+(1|code)+(1|material)+demo.age.years+grit*group+gse*group+tis*group,data=swit_outcome) 

print(summary(lmer_swit_b),cor=F)
print(summary(lmer_swit_e),cor=F)
print(summary(lmer_swit_m),cor=F)

########################################################## DUAL #####################################################################

dual_outcome<-processed_data %>%
  select(code,site,group,sessionId,demo.age.years,grit,tis,gse,dual_draw_rt,dual_numb_rt,dual_shap_rt) %>%
  pivot_longer(cols=ends_with("_rt"),
               names_to="material",
               values_to="_rt") %>%
  pivot_wider(names_from=sessionId, values_from=`_rt`)

dual_outcome$group <- factor(dual_outcome$group, ordered=FALSE)
dual_outcome$group <- relevel(dual_outcome$group, ref="Simple")

lmer_dual_b<-lmer(pretest~group+(1|site)+(1|code)+(1|material)+demo.age.years+grit*group+gse*group+tis*group,data=dual_outcome)
lmer_dual_e<-lmer(posttest~group*pretest+(1|site)+(1|code)+(1|material)+demo.age.years+grit*group+gse*group+tis*group,data=dual_outcome)
lmer_dual_m<-lmer(followup~group*posttest+(1|site)+(1|code)+(1|material)+demo.age.years+grit*group+gse*group+tis*group,data=dual_outcome) 

#singularity issue with maintenance model
isSingular(lmer_dual_m) #true
print(summary(lmer_dual_m),cor=F) #material explains no variance, #respectification below
lmer_dual_m<-lmer(followup~group*posttest+(1|site)+(1|code)+demo.age.years+grit*group+gse*group+tis*group,data=dual_outcome)

#checks

#normality of residual distribution
qqnorm(resid(lmer_dual_b))
qqnorm(resid(lmer_dual_e))
qqnorm(resid(lmer_dual_m))

#homoscedasticity of variance and linearity of model relationships
plot(lmer_dual_b)
plot(lmer_dual_e)
plot(lmer_dual_m)

#remove >=200ms RTs and 3MAD+median< RTs
pps_exclude1<-dual_outcome%>%
  group_by(code) %>%
  filter(any(pretest < 200)) %>%
  filter(any(posttest < 200)) %>%
  filter(any(followup < 200)) %>%
  pull(code) %>% unique() #3 extreme Ids

medianRT1<-median(dual_outcome$pretest)
MAD_3_RT1<-3*mad(dual_outcome$pretest)
medianRT2<-median(dual_outcome$posttest)
MAD_3_RT2<-3*mad(dual_outcome$posttest)
medianRT3<-median(dual_outcome$followup)
MAD_3_RT3<-3*mad(dual_outcome$followup)

pps_exclude2<-dual_outcome%>%
  group_by(code) %>%
  filter(pretest > (medianRT1+MAD_3_RT1)) %>%
  filter(posttest > (medianRT2+MAD_3_RT2)) %>%
  filter(followup > (medianRT3+MAD_3_RT3)) %>%
  pull(code) %>% unique() #4 extreme Ids

extremes<-union(pps_exclude1,pps_exclude2) #7 extreme Ids
dual_outcome<-dual_outcome %>%
  filter(!dual_outcome$code %in% extremes) #removes all data for extreme pps (-21 observations)

#transformation
dual_outcome$pretest<-log(dual_outcome$pretest)
dual_outcome$posttest<-log(dual_outcome$posttest)
dual_outcome$followup<-log(dual_outcome$followup)

#re-run lines 517 and 525-256

#singularity issue for all models - remove site for all, + material for maintanenace
lmer_dual_b<-lmer(pretest~group+(1|code)+(1|material)+demo.age.years+grit*group+gse*group+tis*group,data=dual_outcome)
lmer_dual_e<-lmer(posttest~group*pretest+(1|code)+(1|material)+demo.age.years+grit*group+gse*group+tis*group,data=dual_outcome)
lmer_dual_m<-lmer(followup~group*posttest+(1|code)+demo.age.years+grit*group+gse*group+tis*group,data=dual_outcome)

#cooks distance method
cooksD<-cooks.distance(lmer_dual_b)
influential1<-dual_outcome$code[which(cooksD>1)]
cooksD<-cooks.distance(lmer_dual_e)
influential2<-dual_outcome$code[which(cooksD>1)]
cooksD<-cooks.distance(lmer_dual_m)
influential3<-dual_outcome$code[which(cooksD>1)]
influential<-union(influential1,influential2)
influential<-union(influential,influential3) #16 influential outlying observations; 8 pps
dual_outcome<-dual_outcome[!dual_outcome$code %in% influential, ] #removes all data for extreme pps (-24 observations) (1023 in total)

#z-standardise
dual_outcome$demo.age.years<-scale(dual_outcome$demo.age.years)
dual_outcome$grit<-scale(dual_outcome$grit)
dual_outcome$tis<-scale(dual_outcome$tis)
dual_outcome$gse<-scale(dual_outcome$gse)
dual_outcome$pretest<-scale(dual_outcome$pretest)
dual_outcome$posttest<-scale(dual_outcome$posttest)
dual_outcome$followup<-scale(dual_outcome$followup)

#re-run lines 525-256 and 575

#lack of perfect multicolinearity
multicolinearity_test<-vif(lmer_dual_b, type="predictor") #grit (2.3), gse (2.2)
multicolinearity_test<-vif(lmer_dual_e, type="predictor") #pretest (2.3), grit (2.3), gse (2.2)
multicolinearity_test<-vif(lmer_dual_m, type="predictor") #posttest (2.4), grit (2.3), gse (2.2)

#final models: (1|material) now functions for maintenance model
lmer_dual_b<-lmer(pretest~group+(1|code)+(1|material)+demo.age.years+grit*group+gse*group+tis*group,data=dual_outcome)
lmer_dual_e<-lmer(posttest~group*pretest+(1|code)+(1|material)+demo.age.years+grit*group+gse*group+tis*group,data=dual_outcome)
lmer_dual_m<-lmer(followup~group*posttest+(1|code)+(1|material)+demo.age.years+grit*group+gse*group+tis*group,data=dual_outcome) 

print(summary(lmer_dual_b),cor=F)
print(summary(lmer_dual_e),cor=F)
print(summary(lmer_dual_m),cor=F)

###################################################### REASONING #####################################################################

reas_outcome<-processed_data %>%
  select(code,site,group,sessionId,demo.age.years,grit,tis,gse,assessment.reas.lettersets.score,assessment.reas.paperfolding.score,assessment.reas.rapm.score) %>%
  pivot_longer(cols=ends_with("score"),
               names_to="task",
               values_to="score") %>%
  pivot_wider(names_from=sessionId, values_from=`score`)

reas_outcome$group <- factor(reas_outcome$group, ordered=FALSE)
reas_outcome$group <- relevel(reas_outcome$group, ref="Simple")

lmer_reas_b<-lmer(pretest~group+(1|site)+(1|code)+(1|task)+demo.age.years+grit*group+gse*group+tis*group,data=reas_outcome)
lmer_reas_e<-lmer(posttest~group*pretest+(1|site)+(1|code)+(1|task)+demo.age.years+grit*group+gse*group+tis*group,data=reas_outcome)
lmer_reas_m<-lmer(followup~group*posttest+(1|site)+(1|code)+(1|task)+demo.age.years+grit*group+gse*group+tis*group,data=reas_outcome)

#failure to converge for enhancement model - removal of site random effect resolves
lmer_reas_e<-lmer(posttest~group*pretest+(1|code)+(1|task)+demo.age.years+grit*group+gse*group+tis*group,data=reas_outcome)

#singularity issue with maintenance model
isSingular(lmer_reas_m) #true
print(summary(lmer_reas_m),cor=F) #site explains no variance, #respectification below
lmer_reas_m<-lmer(followup~group*posttest+(1|code)+(1|task)+demo.age.years+grit*group+gse*group+tis*group,data=reas_outcome)

#checks

#normality of residual distribution
qqnorm(resid(lmer_reas_b))
qqnorm(resid(lmer_reas_e))
qqnorm(resid(lmer_reas_m))

#homoscedasticity of variance and linearity of model relationships
plot(lmer_reas_b)
plot(lmer_reas_e)
plot(lmer_reas_m)

#z-standardise
reas_outcome$demo.age.years<-scale(reas_outcome$demo.age.years)
reas_outcome$grit<-scale(reas_outcome$grit)
reas_outcome$tis<-scale(reas_outcome$tis)
reas_outcome$gse<-scale(reas_outcome$gse)
reas_outcome$pretest<-scale(reas_outcome$pretest)
reas_outcome$posttest<-scale(reas_outcome$posttest)
reas_outcome$followup<-scale(reas_outcome$followup)

#re-run lines 625, 630 and 635

#cooks distance method
cooksD<-cooks.distance(lmer_reas_b)
influential1<-reas_outcome$code[which(cooksD>1)]
cooksD<-cooks.distance(lmer_reas_e)
influential2<-reas_outcome$code[which(cooksD>1)]
cooksD<-cooks.distance(lmer_reas_m)
influential3<-reas_outcome$code[which(cooksD>1)]
influential<-union(influential1,influential2)
influential<-union(influential,influential3) #no infuential outliers

#lack of perfect multicolinearity
multicolinearity_test<-vif(lmer_reas_b, type="predictor") #grit (2.2), gse (2.1)
multicolinearity_test<-vif(lmer_reas_e, type="predictor") #pretest (2.1), grit (2.2), gse (2.1)
multicolinearity_test<-vif(lmer_reas_m, type="predictor") #posttest (2), grit (2.2), gse (2.1)

#final models
lmer_reas_b<-lmer(pretest~group+(1|site)+(1|code)+(1|task)+demo.age.years+grit*group+gse*group+tis*group,data=reas_outcome)
lmer_reas_e<-lmer(posttest~group*pretest+(1|code)+(1|task)+demo.age.years+grit*group+gse*group+tis*group,data=reas_outcome)
lmer_reas_m<-lmer(followup~group*posttest+(1|code)+(1|task)+demo.age.years+grit*group+gse*group+tis*group,data=reas_outcome)

print(summary(lmer_reas_b),cor=F)
print(summary(lmer_reas_e),cor=F)
print(summary(lmer_reas_m),cor=F)

################################################## WORKING MEMORY ##################################################################

#z-standardised due to entirely different scaling of task measures
processed_data2<-processed_data
processed_data2$wm.binding.dprime<-scale(processed_data2$wm.binding.dprime)
processed_data2$wm.updating.accuracy<-scale(processed_data2$wm.updating.accuracy)

#wm.error: prior to scaling; absolute valuing and setting as negative so that scoring is based on magnitude, not direction of deviation
processed_data2$wm.reproduction.error<--abs(scale(processed_data2$wm.reproduction.error))

wrme_outcome<-processed_data2 %>%
  select(code,site,group,sessionId,demo.age.years,grit,tis,gse,wm.updating.accuracy,wm.binding.dprime,wm.reproduction.error) %>%
  pivot_longer(cols=starts_with("wm"),
               names_to="task",
               values_to="wm") %>%
  pivot_wider(names_from=sessionId, values_from=`wm`)

wrme_outcome$group <- factor(wrme_outcome$group, ordered=FALSE)
wrme_outcome$group <- relevel(wrme_outcome$group, ref="Simple")

lmer_wrme_b<-lmer(pretest~group+(1|site)+(1|code)+(1|task)+demo.age.years+grit*group+gse*group+tis*group,data=wrme_outcome)
lmer_wrme_e<-lmer(posttest~group*pretest+(1|site)+(1|code)+(1|task)+demo.age.years+grit*group+gse*group+tis*group,data=wrme_outcome)
lmer_wrme_m<-lmer(followup~group*posttest+(1|site)+(1|code)+(1|task)+demo.age.years+grit*group+gse*group+tis*group,data=wrme_outcome)

#singularity issue with enhancement & maintenance model
isSingular(lmer_wrme_e) #true
isSingular(lmer_wrme_m) #true
print(summary(lmer_wrme_e),cor=F) #site explains no variance, #respectification below
print(summary(lmer_wrme_m),cor=F) #site explains no variance, #respectification below
lmer_wrme_e<-lmer(posttest~group*pretest+(1|code)+(1|task)+demo.age.years+grit*group+gse*group+tis*group,data=wrme_outcome) #must retain code
lmer_wrme_m<-lmer(followup~group*posttest+(1|code)+(1|task)+demo.age.years+grit*group+gse*group+tis*group,data=wrme_outcome)

#checks

#normality of residual distribution
qqnorm(resid(lmer_wrme_b))
qqnorm(resid(lmer_wrme_e))
qqnorm(resid(lmer_wrme_m))

#homoscedasticity of variance and linearity of model relationships
plot(lmer_wrme_b)
plot(lmer_wrme_e)
plot(lmer_wrme_m)

#cooks distance method
cooksD<-cooks.distance(lmer_wrme_b)
influential1<-which(cooksD>1)
cooksD<-cooks.distance(lmer_wrme_e)
influential2<-which(cooksD>1)
cooksD<-cooks.distance(lmer_wrme_m)
influential3<-which(cooksD>1) #no outliers deemed as influential

#lack of perfect multicolinearity
multicolinearity_test<-vif(lmer_wrme_b, type="predictor") #*extreme multicolinearity in group w/ group*interaction effects
multicolinearity_test<-vif(lmer_wrme_e, type="predictor") #*
multicolinearity_test<-vif(lmer_wrme_m, type="predictor") #*

#re-specification: removal of cognitive belief interaction effects with group
lmer_wrme_b<-lmer(pretest~group+(1|site)+(1|code)+(1|task)+demo.age.years+grit+gse+tis,data=wrme_outcome)
lmer_wrme_e<-lmer(posttest~group*pretest+(1|code)+(1|task)+demo.age.years+grit+gse+tis,data=wrme_outcome)
lmer_wrme_m<-lmer(followup~group*posttest+(1|code)+(1|task)+demo.age.years+grit+gse+tis,data=wrme_outcome)

#re-check for influential outliers
#cooks distance method
cooksD<-cooks.distance(lmer_wrme_b)
influential1<-which(cooksD>1)
cooksD<-cooks.distance(lmer_wrme_e)
influential2<-which(cooksD>1)
cooksD<-cooks.distance(lmer_wrme_m)
influential3<-which(cooksD>1)
wrme_outcome<-wrme_outcome[-influential2, ] #no outliers deemed as influential
#value 274 outlying is extremely outlying and low on enhancement model; removal did not bias or impact estimates/statistical significance

#final models
lmer_wrme_b<-lmer(pretest~group+(1|site)+(1|code)+(1|task)+demo.age.years+grit+gse+tis,data=wrme_outcome)
lmer_wrme_e<-lmer(posttest~group*pretest+(1|code)+(1|task)+demo.age.years+grit+gse+tis,data=wrme_outcome)
lmer_wrme_m<-lmer(followup~group*posttest+(1|code)+(1|task)+demo.age.years+grit+gse+tis,data=wrme_outcome)

print(summary(lmer_wrme_b),cor=F)
print(summary(lmer_wrme_e),cor=F)
print(summary(lmer_wrme_m),cor=F)

########################################################### MODEL EVALUATIONS ###########################################################################################

model_list<-list(lmer_simp_b,lmer_simp_e,lmer_simp_m,
                 lmer_choi_b,lmer_choi_e,lmer_choi_m,
                 lmer_swit_b,lmer_swit_e,lmer_swit_m,
                 lmer_dual_b,lmer_dual_e,lmer_dual_m,
                 lmer_reas_b,lmer_reas_e,lmer_reas_m,
                 lmer_wrme_b,lmer_wrme_e,lmer_wrme_m)
model_names<-c("lmer_simp_b","lmer_simp_e","lmer_simp_m",
               "lmer_choi_b","lmer_choi_e","lmer_choi_m",
               "lmer_swit_b","lmer_swit_e","lmer_swit_m",
               "lmer_dual_b","lmer_dual_e","lmer_dual_m",
               "lmer_reas_b","lmer_reas_e","lmer_reas_m",
               "lmer_wrme_b","lmer_wrme_e","lmer_wrme_m")
icc_results<-list()
ranova_results<-list()
r_squared_results<-list()

for(i in seq_along(model_list)) {
  model<-model_list[[i]]
  model_name<-model_names[[i]]
  icc_results[[model_name]]<-performance::icc(model)
  ranova_results[[model_name]]<-ranova(model)
  r_squared_results[[model_name]]<-r.squaredGLMM(model,null)
}
print(icc_results)
print(ranova_results)
print(r_squared_results)

################################### post-hoc ANOVAs for checking cognitive beliefs between groups #######################################################################

crb<-crb%>%
  semi_join(processed_data,crb,by="code") #refines to only include final sample

#grit

group_grit<-aov(grit~group, data=crb)
summary(group_grit) #no sig. differences
means_grit<-crb %>%
  group_by(group) %>%
  summarise(mean_grit=mean(grit))
print(means_grit) #Simple=3.55, Choice=3.55, Switching=3.56, Dual=3.49
#Duckworth & Quinn (2009): 3.4 is adult average (range=1-5)

#assumptions
qqnorm(group_grit$residuals) #minor violation, robust as large sample
boxplot(grit~group, xlab='training intervention', ylab='grit', data=crb) #minor violation, robust as similar group sizes

#tis 

group_tis<-aov(tis~group, data=crb)
summary(group_tis) #no sig. differences
means_tis<-crb %>%
  group_by(group) %>%
  summarise(mean_tis=mean(tis))
print(means_tis) #Simple=4.05, Choice=4.12, Switching=4.10, Dual=4.10
#slightly higher than average (3.5), (range=1-6)

#assumptions
qqnorm(group_tis$residuals) #minor violation, robust as large sample
boxplot(tis~group, xlab='training intervention', ylab='tis', data=crb) #minor violation, robust as similar group sizes

#gse 

group_gse<-aov(gse~group, data=crb)
summary(group_gse) #no sig. difference
means_gse<-crb %>%
  group_by(group) %>%
  summarise(mean_gse=mean(gse))
print(means_gse) #Switch=3.13, Simple=3.24, Choice=3.16, Dual=3.2
#slightly higher than average scores (Scholz et al., 2002: 2.9-3.1), (range=1-4) 

#assumptions
qqnorm(group_gse$residuals) #minor violation, robust as large sample
boxplot(gse~group, xlab='training intervention', ylab='gse', data=crb) #minor violation, robust as similar group sizes

#LOG-transformation
crb$grit<-log(crb$grit)
crb$tis<-log(crb$tis)
crb$gse<-log(crb$gse)

#final models
group_grit<-aov(grit~group, data=crb)
group_tis<-aov(tis~group, data=crb)
group_gse<-aov(gse~group, data=crb)
summary(group_grit)
summary(group_tis)
summary(group_gse)