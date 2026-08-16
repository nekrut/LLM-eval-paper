#!/usr/bin/env bash
set -euo pipefail

THREADS=4
RAW=data/raw
REF=data/ref
RESULTS=results
mkdir -p "$RESULTS"

REF_FA="$REF/chrM.fa"
if [ ! -f "${REF_FA}.bwt" ]; then
    bwa index "$REF_FA"
fi

samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

check_done() {
    local s=$1
    [[ -f "${RESULTS}/${s}.bam" && \
       -f "${RESULTS}/${s}.bam.bai" && \
       -f "${RESULTS}/${s}.vcf.gz" && \
       -f "${RESULTS}/${s}.vcf.gz.tbi" ]]
}

all_done=true
for s in "${samples[@]}"; do
    if ! check_done "$s"; then
        all_done=false
        break
    fi
done

if $all_done && [ -f "${RESULTS}/collapsed.tsv" ]; then
    exit 0
fi

for s in "${samples[@]}"; do
    if check_done "$s"; then
        continue
    fi
    fq1="${RAW}/${s}_1.fq.gz"
    fq2="${RAW}/${s}_2.fq.gz"
    bam_out="${RESULTS}/${s}.bam"

    bwa mem -t "$THREADS" "$REF_FA" "$fq1" "$fq2" | \
        samtools view -Sb - | \
        samtools sort -@ "$THREADS" -o "$bam_out"

    samtools index "$bam_out"

    vcf_out="${RESULTS}/${s}.vcf.gz"
    lofreq call -f "$REF_FA" -s "$s" "$bam_out" -o "$vcf_out"

    tabix -p vcf "$vcf_out"
done

collapsed_file="${RESULTS}/collapsed.tsv"
printf "sample\tchrom\tpos\tref\talt\taf\n" > "$collapsed_file"
for s in "${samples[@]}"; do
    bcftools query -f '%SAMPLE\t%CHROM\t%POS\t%REF\t%ALT\t%AF\n' "${RESULTS}/${s}.vcf.gz" >> "$collapsed_file"
done

exit 0