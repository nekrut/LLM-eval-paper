#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF=data/ref/chrM.fa
RESULTS=results

mkdir -p "$RESULTS"

# 2. Reference indexing (once, idempotent)
if [[ ! -f "$REF.fai" ]]; then
    samtools faidx "$REF"
fi
if [[ ! -f "$REF.bwt" ]]; then
    bwa index "$REF"
fi

process_sample() {
    local sample=$1
    local bam="$RESULTS/${sample}.bam"
    local bam_bai="${bam}.bai"
    local vcf="$RESULTS/${sample}.vcf.gz"
    local vcf_tbi="${vcf}.tbi"

    # 3. Alignment (skip if final VCF already exists and is up‑to‑date)
    if [[ -f "$vcf_tbi" && "$vcf_tbi" -nt "data/raw/${sample}_1.fq.gz" && "$vcf_tbi" -nt "data/raw/${sample}_2.fq.gz" ]]; then
        return 0
    fi

    # bwa mem with read group (literal \t)
    bwa mem -t "$THREADS" \
        -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
        "$REF" \
        "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz" |
    samtools sort -@ "$THREADS" -o "$bam"

    # 5. Index BAM
    if [[ ! -f "$bam_bai" || "$bam_bai" -ot "$bam" ]]; then
        samtools index -@ "$THREADS" "$bam"
    fi

    # 6. Variant calling with lofreq (skip if VCF already exists)
    if [[ -f "$vcf_tbi" && "$vcf_tbi" -nt "$bam" ]]; then
        return 0
    fi
    lofreq call-parallel --pp-threads "$THREADS" --verbose \
        --ref "$REF" --out "${RESULTS}/${sample}.vcf" \
        "$bam"

    # 7. Compress and index VCF, cleanup intermediate
    if [[ ! -f "$vcf_tbi" || "$vcf_tbi" -ot "${RESULTS}/${sample}.vcf" ]]; then
        bgzip -c "${RESULTS}/${sample}.vcf" > "$vcf"
        tabix -p vcf "$vcf"
        rm -f "${RESULTS}/${sample}.vcf"
    fi
}

# Process each sample in parallel but respect idempotency
for s in "${SAMPLES[@]}"; do
    process_sample "$s" &
done
wait

# 8. Collapse step (rebuild if any VCF newer than collapsed.tsv)
COLLAPSED="$RESULTS/collapsed.tsv"
if [[ -f "$COLLAPSED" ]] && \
   ! $(for s in "${SAMPLES[@]}"; do
          vcf="${RESULTS}/${s}.vcf.gz"
          if [[ "$vcf" -nt "$COLLAPSED" ]]; then
              echo "newer"
              exit 1
          fi
      done; echo "ok"); then
    # No need to rebuild
    exit 0
fi

{
    echo -e "sample\tchrom\tpos\tref\talt\taf"
    for s in "${SAMPLES[@]}"; do
        vcf="${RESULTS}/${s}.vcf.gz"
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$vcf" |
            awk -v sample="$s" '{print sample "\t" $0}'
    done
} > "$COLLAPSED"

exit 0