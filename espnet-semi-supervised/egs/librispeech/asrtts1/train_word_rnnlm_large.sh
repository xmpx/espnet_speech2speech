
#!/bin/bash

# Copyright 2017 Johns Hopkins University (Shinji Watanabe)
#  Apache 2.0  (http://www.apache.org/licenses/LICENSE-2.0)

. ./path.sh
. ./cmd.sh

# general configuration
backend=pytorch
stage=4       # start from -1 if you need to start from data download
gpu=           # will be deprecated, please use ngpu
ngpu=0         # number of gpus ("0" uses cpu, otherwise use gpu)
nj=64
debugmode=1
dumpdir=dump   # directory to dump full features
N=0            # number of minibatches to be used (mainly for debugging). "0" uses all minibatches.
verbose=0      # verbose option
seed=1         # random seed number
resume=        # Resume the training from snapshot
exp_prefix=""
# feature configuration
do_delta=false # true when using CNN
fs=16000       # sampling frequency
fmax=""        # maximum frequency
fmin=""        # minimum frequency
n_mels=80      # number of mel basis
n_fft=1024     # number of fft points
n_shift=512    # number of shift points
win_length=""  # number of samples in analysis window

# ASR network archtecture
# encoder related
etype=vggblstmp   # encoder architecture type
elayers=4
eunits=320
eprojs=512 # ASR default 320
subsample=1_2_2_1_1 # skip every n frame from input to nth layers
# decoder related
dlayers=1
dunits=300
# attention related
adim=320
atype=location
aconv_chans=10
aconv_filts=100

# hybrid CTC/attention
mtlalpha=0.0

# TTS network archtecture
# encoder related
tts_embed_dim=512
tts_elayers=1
tts_eunits=512
tts_econv_layers=3 # if set 0, no conv layer is used
tts_econv_chans=512
tts_econv_filts=5
# decoder related
tts_dlayers=2
tts_dunits=1024
tts_prenet_layers=2  # if set 0, no prenet is used
tts_prenet_units=256
tts_postnet_layers=5 # if set 0, no postnet is used
tts_postnet_chans=512
tts_postnet_filts=5
tts_use_speaker_embedding=true
# attention related
tts_adim=128
tts_aconv_chans=32
tts_aconv_filts=15      # resulting in filter_size = aconv_filts * 2 + 1
tts_cumulate_att_w=true # whether to cumulate attetion weight
tts_use_batch_norm=true # whether to use batch normalization in conv layer
tts_use_concate=true    # whether to concatenate encoder embedding with decoder lstm outputs
tts_use_residual=false  # whether to use residual connection in encoder convolution
tts_use_masking=true    # whether to mask the padded part in loss calculation
tts_bce_pos_weight=1.0  # weight for positive samples of stop token in cross-entropy calculation

tts_dropout=0.5
tts_zoneout=0.1

# common configurations

# minibatch related
batchsize=32
batch_sort_key="" # empty or input or output (if empty, shuffled batch will be used)
maxlen_in=400  # if input length  > maxlen_in, batchsize is automatically reduced
maxlen_out=150 # if output length > maxlen_out, batchsize is automatically reduced

# optimization related
opt=Adam
lr=1e-3
eps=1e-6
weight_decay=0.0
epochs=10
asr_weight=0.1
tts_weight=1.0
s2s_weight=0.01
t2t_weight=0.01
mmd_weight=0.01
inter_domain_loss=mmd
use_mmd_ae=True
# rnnlm related
lm_weight=0.3

# rnnlm related
use_wordlm=true     # false means to train/use a character LM
lm_vocabsize=65000  # effective only for word LMs
lm_layers=1         # 2 for character LMs
lm_units=1000       # 650 for character LMs
lm_opt=sgd          # adam for character LMs
lm_batchsize=300    # 1024 for character LMs
lm_epochs=60        # number of epochs
lm_maxlen=40        # 150 for character LMs
lm_resume=          # specify a snapshot file to resume LM training
lmtag=              # tag for managing LMs


# decoding parameter
beam_size=20
penalty=0.0
maxlenratio=0.8
minlenratio=0.3
ctc_weight=0.0
recog_model=loss.best # set a model to be used for decoding: 'acc.best' or 'loss.best'

# Set this to somewhere where you want to put your data, or where
# someone else has already put it.  You'll want to change this
# if you're not on the CLSP grid.
datadir=/export/a15/vpanayotov/data
datadir=../asr1/data
datadir=/data/rigel1/corpora/LibriSpeech
# model
model_asr=
model_tts=
model=

# base url for downloads.
data_url=www.openslr.org/resources/12

# exp tag
tag="" # tag for managing experiments.

data_type=data_short_3000 # data or data_short or data_short_p

. utils/parse_options.sh || exit 1;

. ./path.sh
. ./cmd.sh

# check gpu option usage
if [ ! -z ${gpu} ]; then
    echo "WARNING: --gpu option will be deprecated."
    echo "WARNING: please use --ngpu option."
    if [ ${gpu} -eq -1 ]; then
        ngpu=0
    else
        ngpu=1
    fi
fi

# Set bash to 'debug' mode, it will exit on :
# -e 'error', -u 'undefined variable', -o ... 'error in pipeline', -x 'print commands',
set -e
set -u
set -o pipefail

train_set=train_960
train_dev=dev_clean
recog_set="test_clean test_other dev_clean dev_other"

# if [ ${stage} -le -1 ]; then
#     echo "stage -1: Data Download"
#     for part in dev-clean test-clean dev-other test-other train-clean-100 train-clean-360 train-other-500; do
#         local/download_and_untar.sh ${datadir} ${data_url} ${part}
#     done
# fi

# if [ ${stage} -le 0 ]; then
#     ### Task dependent. You have to make data the following preparation part by yourself.
#     ### But you can utilize Kaldi recipes in most cases
#     echo "stage 0: Data preparation"
#     for part in dev-clean test-clean dev-other test-other train-clean-100 train-clean-360 train-other-500; do
#         # use underscore-separated names in data directories.
#         local/data_prep.sh ${datadir}/LibriSpeech/${part} data/$(echo ${part} | sed s/-/_/g)_asr
#         local/data_prep.sh ${datadir}/LibriSpeech/${part} data/$(echo ${part} | sed s/-/_/g)_tts
#     done
# fi

# if [ ${stage} -le 1 ]; then
#     ### Task dependent. You have to design training and dev sets by yourself.
#     ### But you can utilize Kaldi recipes in most cases
#     echo "stage 1: Feature Generation"
#     fbankdir=fbank_asr
#     # Generate the fbank features; by default 80-dimensional fbanks with pitch on each frame
#     for x in dev_clean test_clean dev_other test_other train_clean_100 train_clean_360 train_other_500; do
# 	x=${x}_asr
# 	steps/make_fbank_pitch.sh --cmd "$train_cmd" --nj ${nj} data/${x} exp/make_fbank/${x} ${fbankdir}
#     done
#     fbankdir=fbank_tts
#     for x in dev_clean test_clean dev_other test_other train_clean_100 train_clean_360 train_other_500; do
# 	x=${x}_tts
# 	make_fbank.sh --cmd "${train_cmd}" --nj ${nj} \
# 		      --fs ${fs} \
# 		      --fmax "${fmax}" \
# 		      --fmin "${fmin}" \
# 		      --n_fft ${n_fft} \
# 		      --n_shift ${n_shift} \
# 		      --win_length "${win_length}" \
# 		      --n_mels ${n_mels} \
# 		      data/${x} \
# 		      exp/make_fbank/${x} \
# 		      ${fbankdir}
#     done

#     for mode in asr tts; do
# 	utils/combine_data.sh data/${train_set}_${mode} data/train_clean_100_${mode} data/train_clean_360_${mode} data/train_other_500_${mode}
# 	utils/combine_data.sh data/${train_dev}_${mode} data/dev_clean_${mode} data/dev_other_${mode}

# 	# compute global CMVN
# 	# make sure that we only use the pair data for global normalization
# 	compute-cmvn-stats scp:data/train_clean_100_${mode}/feats.scp data/train_clean_100_${mode}/cmvn.ark

# 	# dump features for training
# 	for task in ${train_set} ${train_dev} ${recog_set}; do
# 	    feat_dir=${dumpdir}/${task}_${mode}/delta${do_delta}; mkdir -p ${feat_dir}
# 	    if [[ $(hostname -f) == *.clsp.jhu.edu ]] && [ ! -d ${feat_dir}/storage ]; then
# 		utils/create_split_dir.pl \
# 		    /export/b{14,15,16,18}/${USER}/espnet-data/egs/librispeech/asrtts1/dump/${task}_${mode}/delta${do_delta}/storage \
# 		    ${feat_dir}/storage
# 	    fi
# 	    dump.sh --cmd "$train_cmd" --nj ${nj} --do_delta ${do_delta} \
# 		    data/${task}_${mode}/feats.scp data/train_clean_100_${mode}/cmvn.ark exp/dump_feats/${task}_${mode} ${feat_dir}
# 	done
#     done
# fi

# dict=data/lang_1char/train_clean_100_units.txt
# echo "dictionary: ${dict}"
# if [ ${stage} -le 2 ]; then
#     ### Task dependent. You have to check non-linguistic symbols used in the corpus.
#     echo "stage 2: Dictionary and Json Data Preparation"
#     mkdir -p data/lang_1char/
#     echo "<unk> 1" > ${dict} # <unk> must be 1, 0 will be used for "blank" in CTC
#     text2token.py -s 1 -n 1 data/train_clean_100_asr/text | cut -f 2- -d" " | tr " " "\n" \
#     | sort | uniq | grep -v -e '^\s*$' | awk '{print $0 " " NR+1}' >> ${dict}
#     wc -l ${dict}

#     # add mode
#     # train_clean_100 for pair data, train_clean_360 for audio only, train_other_500 and/or train_clean_360
#     for mode in asr tts; do
# 	awk '{print $1 " p"}' data/train_clean_100_${mode}/utt2spk >  data/${train_set}_${mode}/utt2mode.scp
# 	awk '{print $1 " a"}' data/train_clean_360_${mode}/utt2spk >> data/${train_set}_${mode}/utt2mode.scp
# 	awk '{print $1 " t"}' data/train_other_500_${mode}/utt2spk >> data/${train_set}_${mode}/utt2mode.scp
# 	# dev set has pair data
# 	awk '{print $1 " p"}' data/${train_dev}_${mode}/utt2spk > data/${train_dev}_${mode}/utt2mode.scp
    
# 	# make json labels
# 	for task in ${train_set} ${train_dev}; do
# 	    feat_dir=${dumpdir}/${task}_${mode}/delta${do_delta}
# 	    data2json.sh --feat ${feat_dir}/feats.scp --scps data/${task}_${mode}/utt2mode.scp \
# 			 data/${task}_${mode} ${dict} > ${feat_dir}/data.json
# 	done
# 	for task in ${recog_set}; do
# 	    feat_dir=${dumpdir}/${task}_${mode}/delta${do_delta}
#             data2json.sh --feat ${feat_dir}/feats.scp \
# 			 data/${task}_${mode} ${dict} > ${feat_dir}/data.json
# 	done
#     done
#     # combine asr and tts jsons as multiple input and output
#     for task in ${train_set} ${train_dev} ${recog_set}; do
# 	feat_dir=${dumpdir}/${task}/delta${do_delta}; mkdir -p ${feat_dir}
# 	local/multi_jsons.py ${dumpdir}/${task}_asr/delta${do_delta}/data.json ${dumpdir}/${task}_tts/delta${do_delta}/data.json \
# 			     > ${feat_dir}/data.json
#     done
# fi

# if [ ${stage} -le 3 ]; then
#     echo "stage 3: x-vector extraction"
#     # Make MFCCs and compute the energy-based VAD for each dataset
#     mfccdir=mfcc
#     vaddir=mfcc
#     nnet_dir=exp/xvector_nnet_1a
#     # for task in ${train_set} ${train_dev} ${recog_set}; do
#     #     (
# 	#         utils/copy_data_dir.sh data/${task}_asr data/${task}_mfcc
# 	#         steps/make_mfcc.sh \
# 	#             --write-utt2num-frames true \
# 	#             --mfcc-config conf/mfcc.conf \
# 	#             --nj ${nj} --cmd "$train_cmd" \
# 	#             data/${task}_mfcc exp/make_mfcc $mfccdir
# 	#         utils/fix_data_dir.sh data/${task}_mfcc
# 	#         sid/compute_vad_decision.sh --nj ${nj} --cmd "$train_cmd" \
# 	# 			                        data/${task}_mfcc exp/make_vad ${vaddir}
# 	#         utils/fix_data_dir.sh data/${task}_mfcc
#     #     )
#     # done
#     # wait
#     # # Check pretrained model existence
#     # # nnet_dir=$PWD/../tts1/
#     # if [ ! -e $nnet_dir ];then
# 	#     echo "X-vector model does not exist. Download pre-trained model."
# 	#     wget http://kaldi-asr.org/models/8/0008_sitw_v2_1a.tar.gz
# 	#     tar xvf 0008_sitw_v2_1a.tar.gz
# 	#     mv 0008_sitw_v2_1a/exp/xvector_nnet_1a exp
# 	#     rm -rf 0008_sitw_v2_1a.tar.gz 0008_sitw_v2_1a
#     # fi
#     # Extract x-vector
#     # for task in ${train_set} ${train_dev} ${recog_set}; do
# 	#     sid/nnet3/xvector/extract_xvectors.sh --cmd "$train_cmd" --nj ${nj} \
# 	# 				                          $nnet_dir data/${task}_mfcc \
# 	# 				                          $nnet_dir/xvectors_${task} &
#     # done
#     # wait
#     # # Update json
#     # for task in ${train_set} ${train_dev} ${recog_set}; do
# 	#     local/update_json.sh ${dumpdir}/${task}/delta${do_delta}/data.json ${nnet_dir}/xvectors_${task}/xvector.scp
#     # done
#     # Finally remove long utterances
#     # Also prepare only parallel data
#     for task in ${train_set} ${train_dev}; do
# 	    feat_dir=${dumpdir}/${task}/delta${do_delta}
# 	    python2 local/remove_longshort_utt.py \
# 	            --max-input 3000 --max-output 400 \
# 	            ${feat_dir}/data.json > ${feat_dir}/data_short_3000.json
# 	    # python2 local/remove_longshort_utt.py \
# 	    #        --max-input 1500 --max-output 300 \
# 	    #        ${feat_dir}/data.json > ${feat_dir}/data_short.json
# 	    # python2 local/prune_json.py ${feat_dir}/data_short.json > ${feat_dir}/data_short_p.json
#     done
# fi

# You can skip this and remove --rnnlm option in the recognition (stage 5)
lmexpdir=exp/train_large_word_rnnlm_2layer_bs256_epoch${lm_epochs}
mkdir -p ${lmexpdir}
if [ ${stage} -le 4 ]; then
    echo "stage 4: LM Preparation"
    # lmdatadir=data/local/lm_train
    # if [ ! -e ${lmdatadir}/valid.txt ]; then
    #     mkdir -p ${lmdatadir}
    #     text2token.py -s 1 -n 1 data/${train_set}_asr/text | cut -f 2- -d" " | perl -pe 's/\n/ <eos> /g' \
    #                                                                                 > ${lmdatadir}/train.txt
    #     text2token.py -s 1 -n 1 data/${train_dev}_asr/text | cut -f 2- -d" " | perl -pe 's/\n/ <eos> /g' \                                                                                    > ${lmdatadir}/valid.txt
    # fi


    lmdatadir=data/local/wordlm_train_large
    lmdict=${lmdatadir}/wordlist_${lm_vocabsize}.txt
    mkdir -p ${lmdatadir}

    cat data/train_clean_100_asr/text data/train_other_500_asr/text | cut -f 2- -d" " > ${lmdatadir}/train.txt
    cat data/${train_dev}_asr/text | cut -f 2- -d" " > ${lmdatadir}/valid.txt
    cat data/test_clean_asr/text | cut -f 2- -d" "  > ${lmdatadir}/test.txt
    text2vocabulary.py -s ${lm_vocabsize} -o ${lmdict} ${lmdatadir}/train.txt

    # use only 1 gpu
    if [ ${ngpu} -gt 1 ]; then
        echo "LM training does not support multi-gpu. signle gpu will be used."
    fi
    ${cuda_cmd} --gpu 1 ${lmexpdir}/train.log \
        lm_train.py \
        --ngpu 1 \
        --backend ${backend} \
        --verbose 1 \
        --outdir ${lmexpdir} \
        --train-label ${lmdatadir}/train.txt \
        --valid-label ${lmdatadir}/valid.txt \
        --test-label ${lmdatadir}/test.txt \
        --resume ${lm_resume} \
        --layer ${lm_layers} \
        --unit ${lm_units} \
        --opt ${lm_opt} \
        --batchsize ${lm_batchsize} \
        --epoch ${lm_epochs} \
        --maxlen ${lm_maxlen} \
        --dict ${lmdict}
        # --resume ./exp/train_large_word_rnnlm_2layer_bs256/snapshot.ep.20
        # --epoch 60 \
        # --batchsize 256 \
        # --dict ${dict}
fi
