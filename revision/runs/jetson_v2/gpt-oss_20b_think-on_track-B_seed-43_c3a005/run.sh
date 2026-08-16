#!/usr/bin/env bash
set -euo pipefail

THREADS=4

RAW=data/raw
REF=data/ref
RESULTS=results

SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p "$RESULTS"

# Index reference for bwa and samtools if needed
if ! [[ -f "${REF}/chrM.fa.bwt" ]]; then
    bwa index "${REF}/chrM.fa"
fi

if ! [[ -f "${REF}/chrM.fa.fai" ]]; then
    samtools faidx "${REF}/chrM.fa"
fi

process_sample() {
    local sample="$1"
    local bam="${RESULTS}/${sample}.bam"
    local bai="${bam}.bai"
    local vcf_gz="${RESULTS}/${sample}.vcf.gz"
    local tbi="${vcf_gz}.tbi"

    if [[ -f "$bam" && -f "$bai" && -f "$vcf_gz" && -f "$tbi" ]]; then
        return 0
    fi

    bwa mem -t "$THREADS" "${REF}/chrM.fa" \
        "${RAW}/${sample}_1.fq.gz" "${RAW}/${sample}_2.fq.gz" |
    samtools view -@ "$THREADS" -b - | \
    samtools sort -@ "$THREADS" -o "$bam"

    samtools index -@ "$THREADS" "$bam"

    lofreq call --call-indels -f "${REF}/chrM.fa" "$bam" -o "${RESULTS}/${sample}.vcf"

    bgzip -c "${RESULTS}/${sample}.vcf" > "$vcf_gz"
    tabix -p vcf "$vcf_gz"
}

for s in "${SAMPLES[@]}"; do
    process_sample "$s"
done

COLLAPSED="${RESULTS}/collapsed.tsv"

if ! [[ -f "$COLLAPSED" ]]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED"
    for s in "${SAMPLES[@]}"; do
        vcf_gz="${RESULTS}/${s}.vcf.gz"
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t[%AF]\n' "$vcf_gz" |
            awk -v sample="$s" 'BEGIN{OFS="\t"} {$0=sample OFS $0}1' >> "$COLLAPSED"
    done
fi

exit 0